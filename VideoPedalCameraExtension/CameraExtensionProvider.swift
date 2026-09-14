import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import IOKit.audio

/// Publishes the "Video Pedal" virtual camera and forwards frames received over XPC from the
/// host app into the stream. This is the whole extension: no third-party code involved.
final class CameraExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    var provider: CMIOExtensionProvider!
    private let deviceSource: CameraExtensionDeviceSource
    private let streamSource: CameraExtensionStreamSource
    private let xpcListener: XPCService

    init(clientQueue: DispatchQueue?) {
        deviceSource = CameraExtensionDeviceSource()
        streamSource = CameraExtensionStreamSource(deviceSource: deviceSource)
        xpcListener = XPCService()
        super.init()

        // `self` is only usable as a reference from this point on (after super.init()), so the
        // provider - which needs `self` as its source - is created here rather than eagerly.
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)

        let device = CMIOExtensionDevice(localizedName: SharedConstants.deviceName,
                                         deviceID: SharedConstants.deviceID, legacyDeviceID: nil, source: deviceSource)
        let stream = CMIOExtensionStream(localizedName: "\(SharedConstants.deviceName) Stream",
                                         streamID: SharedConstants.streamID, direction: .source,
                                         clockType: .hostTime, source: streamSource)
        streamSource.stream = stream
        do {
            try device.addStream(stream)
            try provider.addDevice(device)
        } catch {
            NSLog("VideoPedalCameraExtension: failed to publish device/stream: \(error)")
        }

        xpcListener.frameHandler = { [weak streamSource] surface, timeNs in
            streamSource?.enqueue(surface: surface, hostTimeNs: timeNs)
        }
        xpcListener.start()
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        props.manufacturer = "castdrian"
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}
}

final class CameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        props.model = SharedConstants.deviceName
        props.transportType = Int(kIOAudioDeviceTransportTypeVirtual)
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}
}

final class CameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    weak var stream: CMIOExtensionStream?
    private let deviceSource: CameraExtensionDeviceSource
    private var isStreaming = false
    private let formatDescription: CMFormatDescription

    init(deviceSource: CameraExtensionDeviceSource) {
        self.deviceSource = deviceSource
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA,
                                       width: SharedConstants.outputWidth, height: SharedConstants.outputHeight,
                                       extensions: nil, formatDescriptionOut: &description)
        formatDescription = description!
        super.init()
    }

    var formats: [CMIOExtensionStreamFormat] {
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(SharedConstants.outputFPS))
        return [CMIOExtensionStreamFormat(formatDescription: formatDescription, maxFrameDuration: frameDuration,
                                          minFrameDuration: frameDuration, validFrameDurations: nil)]
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        props.frameDuration = CMTime(value: 1, timescale: CMTimeScale(SharedConstants.outputFPS))
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws { isStreaming = true }

    func stopStream() throws { isStreaming = false }

    /// Called by the XPC listener with a frame the host app already recorded/looped/blended.
    func enqueue(surface: IOSurface, hostTimeNs: UInt64) {
        guard isStreaming, let stream else { return }
        var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
        CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &unmanagedPixelBuffer)
        guard let pixelBuffer = unmanagedPixelBuffer?.takeRetainedValue() else { return }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(SharedConstants.outputFPS)),
                                        presentationTimeStamp: CMTime(value: Int64(hostTimeNs), timescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return }
        let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                              formatDescription: formatDescription, sampleTiming: &timing,
                                                              sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { return }
        stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTimeNs)
    }
}
