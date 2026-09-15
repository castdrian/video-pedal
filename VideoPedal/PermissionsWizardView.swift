import SwiftUI

/// A three-step wizard: Camera access, installing the Video Pedal system camera, then
/// optionally connecting OBS Virtual Camera as a fallback output.
struct PermissionsWizardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("Set up videopedal")
                .font(.title.bold())
            Text("A couple one-time steps, then you're ready to go.")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                WizardStep(
                    number: 1, title: "Camera access",
                    detail: "So videopedal can see your webcam.",
                    done: appState.cameraAuthorized,
                    action: "Grant access", action_: appState.requestCameraAccess)

                WizardStep(
                    number: 2, title: "Install the Video Pedal camera",
                    detail: extensionInstallDetail,
                    done: appState.extensionStatus == .installed,
                    action: "Install", action_: appState.installCameraExtension,
                    disabled: !appState.cameraAuthorized)

                WizardStep(
                    number: 3, title: "Connect OBS Virtual Camera (optional)",
                    detail: obsDetail,
                    done: appState.obsAvailable,
                    action: "Connect", action_: appState.connectOBS,
                    disabled: !appState.cameraAuthorized)
            }
            .padding(24)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            if appState.cameraAuthorized {
                Button("Continue to app") { appState.skipWizard() }
                    .buttonStyle(.link)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: 560)
    }

    private var extensionInstallDetail: String {
        switch appState.extensionStatus {
        case .installed: return "\"Video Pedal\" will show up as a camera in Zoom, Meet, Teams..."
        case .needsUserApproval: return "Approve it in System Settings \u{2192} Privacy & Security, then relaunch."
        case .requiresReboot: return "Installed \u{2014} a reboot may be required the first time."
        case .failed(let message): return "Install failed: \(message)"
        case .unknown: return "Publishes \"Video Pedal\" as a real system camera device."
        }
    }

    private var obsDetail: String {
        return appState.obsAvailable
            ? "OBS Virtual Camera is also receiving frames."
            : "Only needed if you specifically want to feed OBS's own virtual camera instead."
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
