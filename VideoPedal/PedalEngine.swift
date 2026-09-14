import Foundation
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import CoreMedia

enum PedalState: String {
    case live = "LIVE"
    case recording = "REC"
    case looping = "LOOP"
}

/// Compresses frames to JPEG so a long recording stays in RAM instead of growing unbounded,
/// mirroring the Python prototype's JpegCodec.
final class JPEGFrameCodec {
    private let quality: CGFloat
    private let context: CIContext

    init(quality: CGFloat = 0.85, context: CIContext) {
        self.quality = quality
        self.context = context
    }

    func encode(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return context.jpegRepresentation(of: ciImage, colorSpace: colorSpace,
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    func decode(_ data: Data) -> CVPixelBuffer? {
        guard let ciImage = CIImage(data: data) else { return nil }
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }
        context.render(ciImage, to: buffer)
        return buffer
    }
}

/// Frames captured while the pedal is held. Keeps only the newest `maxFrames`, like a tape loop.
final class FrameRecorder {
    private(set) var frames: [Data] = []
    let maxFrames: Int

    init(maxFrames: Int) {
        self.maxFrames = max(1, maxFrames)
        frames.reserveCapacity(self.maxFrames)
    }

    func push(_ frame: Data) {
        frames.append(frame)
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
        }
    }

    var count: Int { frames.count }

    func take() -> [Data] {
        defer { frames.removeAll(keepingCapacity: true) }
        return frames
    }
}

/// Turns a recording into a loop that plays end-to-start without a jump cut by dissolving the
/// last `crossfade` frames into the first `crossfade` frames.
func buildLoop(frames: [Data], crossfade: Int, codec: JPEGFrameCodec, blender: FrameBlender) -> [Data] {
    let n = frames.count
    let k = max(0, min(crossfade, n / 2))
    guard k > 0 else { return frames }
    let body = Array(frames[k..<(n - k)])
    var seam: [Data] = []
    seam.reserveCapacity(k)
    for i in 0..<k {
        let alpha = Double(i + 1) / Double(k + 1)
        guard let tail = codec.decode(frames[n - k + i]), let head = codec.decode(frames[i]),
              let blended = blender.blend(tail, head, alpha: alpha), let data = codec.encode(blended)
        else { continue }
        seam.append(data)
    }
    return body + seam
}

/// Plays back an encoded loop, decoding one frame at a time.
final class FramePlayer {
    private let frames: [Data]
    private let codec: JPEGFrameCodec
    private(set) var position: Int

    init?(frames: [Data], codec: JPEGFrameCodec, start: Int = 0) {
        guard !frames.isEmpty else { return nil }
        self.frames = frames
        self.codec = codec
        self.position = ((start % frames.count) + frames.count) % frames.count
    }

    var count: Int { frames.count }

    func next() -> CVPixelBuffer? {
        let data = frames[position]
        position = (position + 1) % frames.count
        return codec.decode(data)
    }
}

/// Cross-dissolves two pixel buffers using Core Image, reused for the loop seam and the
/// loop-to-live "go live" dissolve. Backed by Metal via the shared CIContext; no third-party deps.
final class FrameBlender {
    private let context: CIContext

    init(context: CIContext) {
        self.context = context
    }

    /// `alpha` 0 = pure `from`, 1 = pure `to`.
    func blend(_ from: CVPixelBuffer, _ to: CVPixelBuffer, alpha: Double) -> CVPixelBuffer? {
        let a = min(1.0, max(0.0, alpha))
        let fromImage = CIImage(cvPixelBuffer: from)
        var toImage = CIImage(cvPixelBuffer: to)
        if toImage.extent.size != fromImage.extent.size {
            let sx = fromImage.extent.width / max(1, toImage.extent.width)
            let sy = fromImage.extent.height / max(1, toImage.extent.height)
            toImage = toImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        guard let filter = CIFilter(name: "CIDissolveTransition") else { return nil }
        filter.setValue(fromImage, forKey: kCIInputImageKey)
        filter.setValue(toImage, forKey: kCIInputTargetImageKey)
        filter.setValue(a, forKey: kCIInputTimeKey)
        guard let output = filter.outputImage else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferCGImageCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(fromImage.extent.width), Int(fromImage.extent.height),
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }
        context.render(output, to: buffer, bounds: fromImage.extent, colorSpace: fromImage.colorSpace)
        return buffer
    }
}

struct PedalHUDInfo {
    var state: PedalState
    var elapsed: Double?
    var total: Double?
    var progress: Double?
}

/// The state machine: LIVE --hold--> RECORDING --release--> LOOPING --live key--> LIVE.
/// A hold shorter than `minSeconds` is ignored. Direct port of the Python prototype's LoopPedal.
final class PedalEngine {
    private(set) var state: PedalState = .live
    let fps: Double

    private let codec: JPEGFrameCodec
    private let blender: FrameBlender
    private let recorder: FrameRecorder
    private let minFrames: Int
    private let crossfade: Int
    private var player: FramePlayer?
    private var fadeLeft: Int = 0
    private let log: (String) -> Void

    init(fps: Double, maxSeconds: Double, minSeconds: Double, crossfadeSeconds: Double,
         codec: JPEGFrameCodec, blender: FrameBlender, log: @escaping (String) -> Void = { print($0) }) {
        self.fps = fps
        self.codec = codec
        self.blender = blender
        self.recorder = FrameRecorder(maxFrames: Int(maxSeconds * fps))
        self.minFrames = max(1, Int(minSeconds * fps))
        self.crossfade = Int(crossfadeSeconds * fps)
        self.log = log
    }

    func pedalDown() {
        if state == .recording { return }
        if fadeLeft > 0 {
            fadeLeft = 0
            player = nil
        }
        _ = recorder.take()
        state = .recording
        log("REC   recording (live feed still going out) - release to loop")
    }

    func pedalUp() {
        guard state == .recording else { return }
        let frames = recorder.take()
        if frames.count < minFrames {
            state = player != nil ? .looping : .live
            log("\(state.rawValue)  tap ignored (hold at least \(String(format: "%.1f", Double(minFrames) / fps))s to record)")
            return
        }
        let loop = buildLoop(frames: frames, crossfade: crossfade, codec: codec, blender: blender)
        let k = min(crossfade, frames.count / 2)
        let start = k > 0 ? loop.count - k - 1 : 0
        player = FramePlayer(frames: loop, codec: codec, start: start)
        state = .looping
        log("LOOP  playing \(String(format: "%.1f", Double(loop.count) / fps))s loop - hold pedal to re-record, live key to go live")
    }

    func toggleRecord() {
        if state == .recording { pedalUp() } else { pedalDown() }
    }

    func goLive() {
        if state == .live { return }
        if state == .looping && fadeLeft > 0 { return }
        _ = recorder.take()
        if state == .looping, crossfade > 0, player != nil {
            fadeLeft = crossfade
            log("LIVE  dissolving loop into live over \(String(format: "%.1f", Double(crossfade) / fps))s")
            return
        }
        player = nil
        fadeLeft = 0
        state = .live
        log("LIVE  live feed - hold the pedal key to record")
    }

    /// Given the newest camera frame, return the frame to publish to the virtual camera.
    func process(_ live: CVPixelBuffer) -> CVPixelBuffer {
        switch state {
        case .recording:
            if let data = codec.encode(live) { recorder.push(data) }
            return live
        case .looping:
            guard let player, let loopFrame = player.next() else { return live }
            if fadeLeft == 0 { return loopFrame }
            let a = (Double(crossfade - fadeLeft) + 1) / Double(crossfade + 1)
            fadeLeft -= 1
            if fadeLeft == 0 {
                self.player = nil
                state = .live
            }
            return blender.blend(loopFrame, live, alpha: a) ?? live
        case .live:
            return live
        }
    }

    func overlay(live: CVPixelBuffer, output: CVPixelBuffer, opacity: Double) -> CVPixelBuffer {
        guard state == .looping, opacity > 0 else { return output }
        return blender.blend(live, output, alpha: opacity) ?? output
    }

    var hudInfo: PedalHUDInfo {
        switch state {
        case .recording:
            let elapsed = Double(recorder.count) / fps
            let total = Double(recorder.maxFrames) / fps
            return PedalHUDInfo(state: state, elapsed: elapsed, total: total, progress: min(1, elapsed / total))
        case .looping:
            guard let player else { return PedalHUDInfo(state: state, elapsed: nil, total: nil, progress: nil) }
            return PedalHUDInfo(state: state, elapsed: Double(player.position) / fps,
                                total: Double(player.count) / fps,
                                progress: Double(player.position) / Double(player.count))
        case .live:
            return PedalHUDInfo(state: state, elapsed: nil, total: nil, progress: nil)
        }
    }
}
