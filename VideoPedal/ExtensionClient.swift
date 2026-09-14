import Foundation
import CoreVideo
import IOSurface

/// Talks to the camera extension over XPC and hands it frames as IOSurfaces (zero-copy).
final class ExtensionClient {
    private var connection: NSXPCConnection?

    func connect() {
        guard connection == nil else { return }
        let connection = XPCConnectionFactory.makeExtensionConnection()
        connection.interruptionHandler = { [weak self] in self?.connection = nil }
        connection.invalidationHandler = { [weak self] in self?.connection = nil }
        connection.resume()
        self.connection = connection
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    /// Copies the pixel buffer into an IOSurface-backed buffer if it isn't already one,
    /// then ships it to the extension. Frames are dropped (not queued) if the XPC pipe is busy.
    func send(_ pixelBuffer: CVPixelBuffer, displayTimeNs: UInt64) {
        guard let proxy = connection?.remoteObjectProxy as? CameraExtensionXPCProtocol else { return }
        guard let surface = Self.ioSurface(from: pixelBuffer) else { return }
        proxy.pushFrame(surface: surface, displayTimeNs: displayTimeNs)
    }

    private static func ioSurface(from pixelBuffer: CVPixelBuffer) -> IOSurface? {
        if let existing = CVPixelBufferGetIOSurface(pixelBuffer) {
            return existing.takeUnretainedValue() as IOSurface
        }
        // Fall back to a copy backed by a fresh IOSurface (the source buffer wasn't IOSurface-backed).
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var copy: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(pixelBuffer),
                            attrs as CFDictionary, &copy)
        guard let copy else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        if let src = CVPixelBufferGetBaseAddress(pixelBuffer), let dst = CVPixelBufferGetBaseAddress(copy) {
            memcpy(dst, src, CVPixelBufferGetDataSize(pixelBuffer))
        }
        guard let surfaceRef = CVPixelBufferGetIOSurface(copy) else { return nil }
        return surfaceRef.takeUnretainedValue() as IOSurface
    }
}
