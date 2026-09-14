import SwiftUI

/// A three-step wizard: Camera access, Input Monitoring (for the global pedal key), then
/// installing the camera system extension. Each step re-checks its own status live.
struct PermissionsWizardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("Set up Video Pedal")
                .font(.title.bold())
            Text("Three one-time steps, then you're ready to go.")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                WizardStep(
                    number: 1, title: "Camera access",
                    detail: "So Video Pedal can see your webcam.",
                    done: appState.cameraAuthorized,
                    action: "Grant access", action_: appState.requestCameraAccess)

                WizardStep(
                    number: 2, title: "Input Monitoring",
                    detail: "So the pedal key works even when another app is focused.",
                    done: appState.inputMonitoringAuthorized,
                    action: "Open System Settings", action_: appState.requestInputMonitoring)

                WizardStep(
                    number: 3, title: "Install the virtual camera",
                    detail: extensionDetail,
                    done: appState.extensionStatus == .installed,
                    action: "Install", action_: appState.installExtension,
                    disabled: !(appState.cameraAuthorized && appState.inputMonitoringAuthorized))
            }
            .padding(24)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: 560)
    }

    private var extensionDetail: String {
        switch appState.extensionStatus {
        case .needsUserApproval:
            return "Approve \"Video Pedal\" in System Settings \u{2192} Privacy & Security."
        case .failed(let message):
            return "Failed: \(message)"
        case .requiresReboot:
            return "Installed. A logout/restart may be needed the first time."
        default:
            return "Publishes \"Video Pedal\" as a selectable camera in Zoom, Meet, Teams..."
        }
    }
}

private struct WizardStep: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let action: String
    let action_: () -> Void
    var disabled: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.25))
                Image(systemName: done ? "checkmark" : "\(number).circle.fill")
                    .foregroundStyle(done ? .white : .secondary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !done {
                Button(action, action: action_).disabled(disabled)
            }
        }
    }
}
