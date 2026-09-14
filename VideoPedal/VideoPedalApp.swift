import SwiftUI

@main
struct VideoPedalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}

/// Shows the permission wizard until everything required is granted, then the main window.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private var allSet: Bool {
        appState.cameraAuthorized && appState.inputMonitoringAuthorized && appState.extensionStatus == .installed
    }

    var body: some View {
        Group {
            if allSet {
                ContentView()
                    .onAppear { appState.start() }
                    .onDisappear { appState.stop() }
            } else {
                PermissionsWizardView()
            }
        }
    }
}
