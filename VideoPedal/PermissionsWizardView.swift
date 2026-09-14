import SwiftUI

/// A two-step wizard: Camera access, then installing the camera system extension.
struct PermissionsWizardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("Set up videopedal")
                .font(.title.bold())
            Text("Three one-time steps, then you're ready to go.")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                WizardStep(
                    number: 1, title: "Camera access",
                    detail: "So videopedal can see your webcam.",
                    done: appState.cameraAuthorized,
                    action: "Grant access", action_: appState.requestCameraAccess)

                WizardStep(
                    number: 2, title: "Install the virtual camera",
                    detail: extensionDetail,
                    done: appState.obsAvailable,
                    action: "Install", action_: appState.installExtension,
                    disabled: !appState.cameraAuthorized)
            }
            .padding(24)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: 560)
    }

    private var extensionDetail: String {
        return appState.obsAvailable
            ? "OBS Virtual Camera is ready for Zoom, Meet, Teams..."
            : "Start OBS Virtual Camera once, then click Connect."
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
