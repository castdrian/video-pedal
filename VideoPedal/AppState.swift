import Foundation
import AVFoundation
import CoreImage
import Combine
import SwiftUI

/// Ties together capture, the pedal state machine, the hotkey monitor and the extension
/// XPC client. Owns the render loop that pushes frames to the virtual camera.
@MainActor
final class AppState: ObservableObject {
    @Published var pedalKey: PedalKey = .rightOption
    @Published var liveKey: PedalKey = .rightCommand
    @Published var overlayOpacity: Double = 0.5
    @Published var maxSeconds: Double = 30
    @Published var minSeconds: Double = 1
    @Published var crossfadeSeconds: Double = 0.5

    @Published var cameraAuthorized = CameraCaptureManager.isAuthorized
    @Published var inputMonitoringAuthorized = HotkeyMonitor.inputMonitoringGranted
    @Published private(set) var extensionStatus: ExtensionInstaller.Status = .unknown

    @Published var selectedCamera: AVCaptureDevice?
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var hud = PedalHUDInfo(state: .live, elapsed: nil, total: nil, progress: nil)
    @Published private(set) var pedalEnabled = false
    @Published private(set) var logLines: [String] = []

    let extensionInstaller = ExtensionInstaller()
    private let capture = CameraCaptureManager()
    private let extensionClient = ExtensionClient()
    private var hotkey: HotkeyMonitor?
    private var engine: PedalEngine?
    private var cancellables: Set<AnyCancellable> = []

    private let ciContext = CIContext()
    private lazy var codec = JPEGFrameCodec(context: ciContext)
    private lazy var blender = FrameBlender(context: ciContext)

    var availableCameras: [AVCaptureDevice] { CameraCaptureManager.availableCameras() }

    init() {
        extensionInstaller.$status.receive(on: RunLoop.main).sink { [weak self] in self?.extensionStatus = $0 }
            .store(in: &cancellables)
    }

    func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("\(stamp)  \(message)")
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
    }

    // MARK: - Permission wizard steps

    func requestCameraAccess() {
        CameraCaptureManager.requestAccess { [weak self] granted in self?.cameraAuthorized = granted }
    }

    func requestInputMonitoring() {
        HotkeyMonitor.requestInputMonitoring()
        // The user has to grant this in System Settings; poll briefly for the change.
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let granted = HotkeyMonitor.inputMonitoringGranted
                await MainActor.run { self.inputMonitoringAuthorized = granted }
                if granted { break }
            }
        }
    }

    func installExtension() {
        extensionInstaller.activate()
    }

    // MARK: - Runtime

    func start() {
        engine = PedalEngine(fps: Double(SharedConstants.outputFPS), maxSeconds: maxSeconds, minSeconds: minSeconds,
                             crossfadeSeconds: crossfadeSeconds, codec: codec, blender: blender,
                             log: { [weak self] in self?.log($0) })

        extensionClient.connect()

        capture.onFrame = { [weak self] pixelBuffer in
            guard let self else { return }
            Task { @MainActor in self.handle(pixelBuffer) }
        }
        do {
            try capture.start(device: selectedCamera, width: SharedConstants.outputWidth,
                             height: SharedConstants.outputHeight, fps: Double(SharedConstants.outputFPS))
            log("Camera started: \(selectedCamera?.localizedName ?? "default")")
        } catch {
            log("Camera error: \(error.localizedDescription)")
        }

        let hotkey = HotkeyMonitor(pedalKey: pedalKey, liveKey: liveKey)
        hotkey.onEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                switch event {
                case .down: self.engine?.pedalDown()
                case .up: self.engine?.pedalUp()
                case .live: self.engine?.goLive()
                }
                self.log(self.engine?.state.rawValue ?? "")
            }
        }
        pedalEnabled = hotkey.start()
        self.hotkey = pedalEnabled ? hotkey : nil
        if !pedalEnabled {
            log("Input Monitoring isn't granted, so the global pedal/live keys are off.")
        }
    }

    func stop() {
        capture.stop()
        hotkey?.stop()
        hotkey = nil
        extensionClient.disconnect()
    }

    func toggleRecordFromUI() { engine?.toggleRecord() }
    func goLiveFromUI() { engine?.goLive() }

    private var frameCount: UInt64 = 0

    private func handle(_ pixelBuffer: CVPixelBuffer) {
        guard let engine else { return }
        let output = engine.process(pixelBuffer)
        let shown = engine.overlay(live: pixelBuffer, output: output, opacity: overlayOpacity)

        frameCount += 1
        let hostTimeNs = UInt64(DispatchTime.now().uptimeNanoseconds)
        extensionClient.send(output, displayTimeNs: hostTimeNs)

        hud = engine.hudInfo
        if frameCount % 2 == 0, let cgImage = ciContext.createCGImage(CIImage(cvPixelBuffer: shown), from: CIImage(cvPixelBuffer: shown).extent) {
            previewImage = cgImage
        }
    }
}
