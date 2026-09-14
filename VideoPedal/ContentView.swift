import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                previewArea
                hudBar
            }
            .frame(minWidth: 480)

            SettingsPanel()
                .frame(minWidth: 260, maxWidth: 320)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image = appState.previewImage {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(x: -1, y: 1)  // mirror the self-view only
                } else {
                    ProgressView("Waiting for camera\u{2026}").foregroundStyle(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var hudBar: some View {
        HStack(spacing: 12) {
            StateBadge(state: appState.hud.state)
            if let elapsed = appState.hud.elapsed {
                if let total = appState.hud.total, appState.hud.state == .looping {
                    Text(String(format: "%.1f / %.1fs", elapsed, total)).monospacedDigit()
                } else {
                    Text(String(format: "%.1fs", elapsed)).monospacedDigit()
                }
            }
            Spacer()
            Button(appState.hud.state == .recording ? "Stop (R)" : "Record (R)") {
                appState.toggleRecordFromUI()
            }
            Button("Go live (L)") { appState.goLiveFromUI() }
                .disabled(appState.hud.state == .live)
        }
        .padding(10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            if let progress = appState.hud.progress {
                GeometryReader { proxy in
                    Rectangle().fill(Color.accentColor)
                        .frame(width: proxy.size.width * progress, height: 3)
                }
                .frame(height: 3)
            }
        }
    }
}

private struct StateBadge: View {
    let state: PedalState

    var color: Color {
        switch state {
        case .live: return .green
        case .recording: return .red
        case .looping: return .blue
        }
    }

    var body: some View {
        Text(state.rawValue)
            .font(.headline.monospaced())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct SettingsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Camera") {
                Picker("Source", selection: $appState.selectedCamera) {
                    ForEach(appState.availableCameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                    }
                }
            }

            Section("Pedal") {
                Picker("Record/loop key", selection: $appState.pedalKey) {
                    ForEach(PedalKey.allCases) { key in Text(key.label).tag(key) }
                }
                Picker("Go-live key", selection: $appState.liveKey) {
                    ForEach(PedalKey.allCases) { key in Text(key.label).tag(key) }
                }
            }

            Section("Loop") {
                LabeledContent("Max length") {
                    Slider(value: $appState.maxSeconds, in: 5...60, step: 1)
                    Text("\(Int(appState.maxSeconds))s").monospacedDigit()
                }
                LabeledContent("Min hold") {
                    Slider(value: $appState.minSeconds, in: 0.2...3, step: 0.1)
                    Text(String(format: "%.1fs", appState.minSeconds)).monospacedDigit()
                }
                LabeledContent("Crossfade") {
                    Slider(value: $appState.crossfadeSeconds, in: 0...2, step: 0.1)
                    Text(String(format: "%.1fs", appState.crossfadeSeconds)).monospacedDigit()
                }
                LabeledContent("Preview ghost") {
                    Slider(value: $appState.overlayOpacity, in: 0...1, step: 0.05)
                    Text(String(format: "%.0f%%", appState.overlayOpacity * 100)).monospacedDigit()
                }
            }

            Section("Log") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(appState.logLines.suffix(40).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .formStyle(.grouped)
    }
}
