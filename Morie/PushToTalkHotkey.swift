import AppKit
import ApplicationServices
import Foundation

/// Minimal macOS 27 voice-capture shortcut.
///
/// Morie intentionally supports one focused keyboard interaction here. This is
/// not a generalized hotkey subsystem: no media keys, mouse buttons, modes, or
/// legacy compatibility paths.
final class PushToTalkHotkey {
    enum StartError: LocalizedError {
        case accessibilityUnavailable
        case eventTapCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityUnavailable:
                "Accessibility permission is required for the global voice-capture shortcut."
            case .eventTapCreationFailed:
                "Morie could not install the global voice-capture shortcut."
            }
        }
    }

    private static let shortcutKeyCode = CGKeyCode(49) // Space
    private static let escapeKeyCode = CGKeyCode(53)
    private static let requiredModifiers: CGEventFlags = [.maskControl]
    private static let relevantModifiers: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    private let onToggle: () -> Void
    private let onCancel: () -> Void
    private let onUnavailable: (Error) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcutPressOwned = false
    private var escapePressOwned = false
    private var cancellationEnabled = false

    init(
        onToggle: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUnavailable: @escaping (Error) -> Void
    ) {
        self.onToggle = onToggle
        self.onCancel = onCancel
        self.onUnavailable = onUnavailable
    }

    deinit {
        invalidate()
    }

    func start() throws {
        guard eventTap == nil else {
            Diagnostics.record("Hotkey", "start() ignored because event tap already exists")
            return
        }

        let trusted = AXIsProcessTrusted()
        Diagnostics.record("Hotkey", "Installing Control+Space toggle event tap; accessibilityTrusted=\(trusted)")
        guard trusted else {
            throw StartError.accessibilityUnavailable
        }

        let mask = Self.mask(for: .keyDown) | Self.mask(for: .keyUp)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: moriePushToTalkEventTapCallback,
            userInfo: userInfo
        ) else {
            Diagnostics.record("Hotkey", "CGEvent.tapCreate returned nil", level: .error)
            throw StartError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            Diagnostics.record("Hotkey", "Event tap exists but is not enabled", level: .error)
            invalidate()
            throw StartError.eventTapCreationFailed
        }

        Diagnostics.record("Hotkey", "Control+Space toggle event tap installed and enabled")
    }

    func setCancellationEnabled(_ enabled: Bool) {
        guard cancellationEnabled != enabled else { return }
        cancellationEnabled = enabled
        Diagnostics.record("Hotkey", "Escape cancellation enabled=\(enabled)")
    }

    func invalidate() {
        let hadTap = eventTap != nil
        shortcutPressOwned = false
        escapePressOwned = false
        cancellationEnabled = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }

        runLoopSource = nil
        eventTap = nil

        if hadTap {
            Diagnostics.record("Hotkey", "Event tap invalidated")
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Diagnostics.record("Hotkey", "Event tap disabled by system; attempting recovery", level: .warning)
            recoverEventTapIfPossible()
            return Unmanaged.passUnretained(event)
        }

        if TextInjector.isSyntheticInput(event) {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == Self.shortcutKeyCode {
            return handleShortcut(type: type, event: event)
        }

        if keyCode == Self.escapeKeyCode {
            return handleEscape(type: type, event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleShortcut(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            guard Self.hasExactShortcutModifiers(event.flags) else {
                if event.flags.contains(.maskControl) {
                    Diagnostics.record(
                        "Hotkey",
                        "Space keyDown ignored because modifiers were not exactly Control; flags=0x\(String(event.flags.rawValue, radix: 16))",
                        level: .warning
                    )
                }
                return Unmanaged.passUnretained(event)
            }

            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 || shortcutPressOwned {
                Diagnostics.record("Hotkey", "Control+Space repeat suppressed")
                return nil
            }

            shortcutPressOwned = true
            Diagnostics.record("Hotkey", "Control+Space keyDown accepted; toggling capture")
            onToggle()
            return nil

        case .keyUp:
            guard shortcutPressOwned else {
                return Unmanaged.passUnretained(event)
            }

            shortcutPressOwned = false
            Diagnostics.record("Hotkey", "Control+Space keyUp accepted; capture state unchanged")
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleEscape(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            guard cancellationEnabled else {
                return Unmanaged.passUnretained(event)
            }

            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 || escapePressOwned {
                return nil
            }

            escapePressOwned = true
            Diagnostics.record("Hotkey", "Escape keyDown accepted; cancelling capture")
            onCancel()
            return nil

        case .keyUp:
            guard escapePressOwned else {
                return Unmanaged.passUnretained(event)
            }

            escapePressOwned = false
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func recoverEventTapIfPossible() {
        guard let tap = eventTap else {
            Diagnostics.record("Hotkey", "Cannot recover event tap because it no longer exists", level: .error)
            return
        }

        guard AXIsProcessTrusted() else {
            Diagnostics.record("Hotkey", "Event tap recovery failed: Accessibility trust lost", level: .error)
            invalidate()
            onUnavailable(StartError.accessibilityUnavailable)
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            Diagnostics.record("Hotkey", "Event tap recovery failed after re-enable", level: .error)
            invalidate()
            onUnavailable(StartError.eventTapCreationFailed)
            return
        }

        Diagnostics.record("Hotkey", "Event tap recovered")
    }

    private static func hasExactShortcutModifiers(_ flags: CGEventFlags) -> Bool {
        flags.intersection(relevantModifiers) == requiredModifiers
    }

    private static func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }
}

private func moriePushToTalkEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let hotkey = Unmanaged<PushToTalkHotkey>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    return hotkey.handle(type: type, event: event)
}
