import CoreVideo

final class OBSOutputClient {
    private var output: VPOBSOutputRef?
    var isAvailable: Bool { output != nil }

    func connect(width: Int32, height: Int32) {
        disconnect()
        output = VPOBSOutputCreate(width, height)
    }

    func disconnect() {
        if let output { VPOBSOutputDestroy(output) }
        output = nil
    }

    func send(_ pixelBuffer: CVPixelBuffer, hostTimeNs: UInt64) {
        guard let output else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        _ = VPOBSOutputSendBGRA(output, baseAddress.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetBytesPerRow(pixelBuffer), hostTimeNs)
    }
}