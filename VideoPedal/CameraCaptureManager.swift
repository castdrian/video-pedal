import AVFoundation
import CoreVideo

/// Captures from the physical webcam and hands frames to a closure on a dedicated queue.
final class CameraCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "dev.castdrian.videopedal.capture")
    private var device: AVCaptureDevice?

    var onFrame: ((CVPixelBuffer) -> Void)?

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async { completion(granted) } }
        default:
            completion(false)
        }
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// Real webcams only: excludes this app's own virtual camera so it can't feed itself.
    static func availableCameras() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices
            .filter { $0.modelID != SharedConstants.deviceName }
    }

    func start(device requested: AVCaptureDevice?, width: Int32, height: Int32, fps: Double) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let camera = requested ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
        guard let camera else { throw CaptureError.noCamera }
        self.device = camera

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            // IOSurface-backed so frames can cross the XPC boundary to the extension without a copy.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)

        configureFormat(camera: camera, width: width, height: height, fps: fps)

        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    private func configureFormat(camera: AVCaptureDevice, width: Int32, height: Int32, fps: Double) {
        guard let bestFormat = camera.formats.first(where: {
            let dims = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return dims.width >= width && dims.height >= height
        }) else { return }
        do {
            try camera.lockForConfiguration()
            camera.activeFormat = bestFormat
            let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
            camera.unlockForConfiguration()
        } catch {
            // Non-fatal: the camera keeps its default format.
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }

    enum CaptureError: LocalizedError {
        case noCamera, cannotAddInput, cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera found."
            case .cannotAddInput: return "Could not add the camera as a capture input."
            case .cannotAddOutput: return "Could not add the frame output."
            }
        }
    }
}
