import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            // Higher priority so the fixed-height control bar always keeps its space and
            // only the flexible video area gets compressed when the window shrinks.
            hudBar
                .layoutPriority(1)
        }
        .background(Color.black)
        .background(WindowAspectRatio(ratio: CGSize(width: 16, height: 10)))
        .toolbar {
            ToolbarItem {
                Button {
                    appState.connectOBS()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reconnect OBS Virtual Camera")
                .disabled(appState.obsAvailable)
            }
            ToolbarItem {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Open Settings")
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            Color.black
            if let image = appState.previewImage {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: -1, y: 1)
                    .clipped()
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(appState.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
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
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                appState.toggleRecordFromUI()
            } label: {
                Label(appState.hud.state == .recording ? "Stop" : "Record", systemImage: appState.hud.state == .recording ? "stop.fill" : "record.circle")
            }
            .keyboardShortcut("r", modifiers: [])
            Button {
                appState.goLiveFromUI()
            } label: {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
            }
            .keyboardShortcut("l", modifiers: [])
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

struct SettingsView: View {
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

            DisclosureGroup("Activity") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(appState.logLines.suffix(20).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 110)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
    }
}
