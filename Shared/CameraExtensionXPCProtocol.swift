import Foundation
import CoreMedia
import IOSurface

/// XPC interface exposed by the camera extension. The host app is the client: it pushes
/// processed frames (already recorded/looped/blended) for the extension to hand to callers.
@objc protocol CameraExtensionXPCProtocol {
    /// One video frame, backed by an IOSurface so it crosses the XPC boundary without a copy.
    func pushFrame(surface: IOSurface, displayTimeNs: UInt64)

    /// Lets the host app know whether any client (Zoom, Meet, ...) is actually using the camera,
    /// so it can pause capture when nobody is watching.
    func addStreamingObserver(reply: @escaping (Bool) -> Void)
}

/// XPC interface exposed by the host app, so the extension can report whether a client connected.
@objc protocol VideoPedalHostXPCProtocol {
    func extensionStreamingStateDidChange(_ streaming: Bool)
}

enum XPCConnectionFactory {
    static func makeExtensionConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: CameraExtensionXPCProtocol.self)
        return connection
    }
}
