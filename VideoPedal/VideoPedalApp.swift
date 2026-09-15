import SwiftUI

@main
struct VideoPedalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 700, minHeight: 438)
        }
        .defaultSize(width: 800, height: 500)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 420, height: 420)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.wizardSkipped
                && (!appState.cameraAuthorized || appState.extensionStatus == .unknown || appState.extensionStatus == .needsUserApproval) {
                PermissionsWizardView()
            } else {
                ContentView()
            }
        }
        .onAppear { appState.start() }
        .onDisappear { appState.stop() }
    }
}
