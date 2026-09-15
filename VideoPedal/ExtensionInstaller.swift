import Foundation
import SystemExtensions

/// Installs (and can remove) the camera system extension, and reports status for the wizard.
final class ExtensionInstaller: NSObject, ObservableObject {
    enum Status: Equatable {
        case unknown, installed, needsUserApproval, requiresReboot, failed(String)
    }

    @Published private(set) var status: Status = .unknown

    private var activationContinuation: ((Status) -> Void)?

    func activate() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: SharedConstants.cameraExtensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivate() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: SharedConstants.cameraExtensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

extension ExtensionInstaller: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                didFinishWithResult result: OSSystemExtensionRequest.Result) {
        NSLog("VideoPedal: extension activation finished with result: \(result.rawValue)")
        status = result == .completed ? .installed : .requiresReboot
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        NSLog("VideoPedal: extension activation failed: \(error)")
        status = .failed(error.localizedDescription)
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        NSLog("VideoPedal: extension activation needs user approval in System Settings.")
        status = .needsUserApproval
    }

    func request(_ request: OSSystemExtensionRequest,
                actionForReplacingExtension existing: OSSystemExtensionProperties,
                withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}
