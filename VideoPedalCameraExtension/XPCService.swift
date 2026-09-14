import Foundation
import IOSurface

/// Listens on the shared mach service and hands incoming frames to the stream source.
final class XPCService: NSObject, NSXPCListenerDelegate, CameraExtensionXPCProtocol {
    private let listener: NSXPCListener
    private var connections: [NSXPCConnection] = []

    var frameHandler: ((IOSurface, UInt64) -> Void)?

    override init() {
        listener = NSXPCListener(machServiceName: SharedConstants.machServiceName)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: CameraExtensionXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let newConnection else { return }
            connections.removeAll { $0 === newConnection }
        }
        connections.append(newConnection)
        newConnection.resume()
        return true
    }

    func pushFrame(surface: IOSurface, displayTimeNs: UInt64) {
        frameHandler?(surface, displayTimeNs)
    }

    func addStreamingObserver(reply: @escaping (Bool) -> Void) {
        reply(true)
    }
}
