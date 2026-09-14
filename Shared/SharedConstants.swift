import Foundation

/// Identifiers shared between the host app and the camera extension. Both targets
/// compile this file directly (no framework/dependency needed to share it).
enum SharedConstants {
    static let cameraExtensionBundleID = "dev.castdrian.videopedal.cameraextension"
    static let machServiceName = "dev.castdrian.videopedal.cameraextension.xpc"
    static let appGroupID = "group.dev.castdrian.videopedal"

    /// The virtual camera's fixed identity, so macOS remembers it across relaunches.
    static let deviceID = UUID(uuidString: "8B0F6C60-6E9B-4B3C-9B1E-5B7B6C7E5A10")!
    static let streamID = UUID(uuidString: "3C2C9C9B-2C1E-4D3B-9B0A-1E7C9C6B5A21")!

    static let deviceName = "Video Pedal"
    static let outputWidth: Int32 = 1280
    static let outputHeight: Int32 = 720
    static let outputFPS: Int32 = 30
}
