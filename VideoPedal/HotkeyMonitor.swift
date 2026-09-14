import Foundation
import CoreGraphics
import IOKit.hid
import Carbon.HIToolbox

/// A key the pedal can be bound to. Deliberately a small closed set (instead of parsing arbitrary
/// key names like the Python prototype did) so the permission wizard can show a plain picker.
enum PedalKey: String, CaseIterable, Identifiable, Codable {
    case rightOption, rightCommand, rightControl, rightShift
    case f13, f14, f15, f16, f17, f18, f19

    var id: String { rawValue }

    var isModifier: Bool {
        switch self {
        case .rightOption, .rightCommand, .rightControl, .rightShift: return true
        default: return false
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .rightOption: return CGKeyCode(kVK_RightOption)
        case .rightCommand: return CGKeyCode(kVK_RightCommand)
        case .rightControl: return CGKeyCode(kVK_RightControl)
        case .rightShift: return CGKeyCode(kVK_RightShift)
        case .f13: return CGKeyCode(kVK_F13)
        case .f14: return CGKeyCode(kVK_F14)
        case .f15: return CGKeyCode(kVK_F15)
        case .f16: return CGKeyCode(kVK_F16)
        case .f17: return CGKeyCode(kVK_F17)
        case .f18: return CGKeyCode(kVK_F18)
        case .f19: return CGKeyCode(kVK_F19)
        }
    }

    /// The standard CGEventFlags bit that goes with this modifier while it (or its twin) is held.
    var modifierMask: CGEventFlags? {
        switch self {
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .rightOption: return "right Option"
        case .rightCommand: return "right Command"
        case .rightControl: return "right Control"
        case .rightShift: return "right Shift"
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19:
            return "F\(rawValue.dropFirst())"
        }
    }
}

/// Listens system-wide for the pedal key (hold = record/loop) and the live key (tap = go live),
/// ignoring OS-level chatter on modifier keys in a non-sandboxed macOS app.
final class HotkeyMonitor {
    enum Event { case down, up, live }

    /// macOS can report a spurious release+press pair for a held modifier key (flagsChanged
    /// chatter). A real release is trusted only after it survives this long unchallenged.
    private static let releaseDebounce: TimeInterval = 0.15

    var onEvent: ((Event) -> Void)?

    private var pedalKey: PedalKey
    private var liveKey: PedalKey?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var pedalHeld = false
    private var liveHeld = false
    private var liveSolo = false
    private var releaseGeneration = 0

    init(pedalKey: PedalKey, liveKey: PedalKey?) {
        self.pedalKey = pedalKey
        self.liveKey = liveKey
    }

    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged {
            if pedalKey.isModifier, keyCode == pedalKey.keyCode {
                let down = event.flags.contains(pedalKey.modifierMask ?? [])
                down ? pedalPressed() : pedalReleased()
            }
            if let liveKey, liveKey.isModifier, keyCode == liveKey.keyCode {
                let down = event.flags.contains(liveKey.modifierMask ?? [])
                down ? livePressed() : liveReleased()
            } else if pedalKey.isModifier == false || keyCode != pedalKey.keyCode {
                noteOtherKeyActivity()
            }
            return
        }

        if type == .keyDown {
            if !pedalKey.isModifier, keyCode == pedalKey.keyCode {
                pedalPressed()
            } else {
                noteOtherKeyActivity()
            }
        } else if type == .keyUp {
            if !pedalKey.isModifier, keyCode == pedalKey.keyCode {
                pedalReleased()
            }
        }
    }

    // MARK: - Pedal key (down/up), debounced against modifier-key chatter

    private func pedalPressed() {
        releaseGeneration += 1  // cancels any pending debounced release
        guard !pedalHeld else { return }
        pedalHeld = true
        onEvent?(.down)
    }

    private func pedalReleased() {
        guard pedalHeld else { return }
        releaseGeneration += 1
        let generation = releaseGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDebounce) { [weak self] in
            guard let self, self.releaseGeneration == generation else { return }
            self.pedalHeld = false
            self.onEvent?(.up)
        }
    }

    // MARK: - Live key (solo tap only; a shortcut like live+Tab must not trigger it)

    private func livePressed() {
        guard !liveHeld else { return }
        liveHeld = true
        liveSolo = true
    }

    private func liveReleased() {
        guard liveHeld else { return }
        liveHeld = false
        if liveSolo { onEvent?(.live) }
    }

    private func noteOtherKeyActivity() {
        if liveHeld { liveSolo = false }
    }
}
