import AppKit
import ApplicationServices
import Foundation

/// Minimal macOS 27 push-to-talk hotkey.
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
                "Accessibility permission is required for the global push-to-talk shortcut."
            case .eventTapCreationFailed:
                "Morie could not install the global push-to-talk shortcut."
            }
        }
    }

    private static let shortcutKeyCode = CGKeyCode(49) // Space
    private static let requiredModifiers: CGEventFlags = [.maskControl]
    private static let relevantModifiers: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onUnavailable: (Error) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    init(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onUnavailable: @escaping (Error) -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
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
        Diagnostics.record("Hotkey", "Installing Control+Space event tap; accessibilityTrusted=\(trusted)")
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

        Diagnostics.record("Hotkey", "Control+Space event tap installed and enabled")
    }

    func invalidate() {
        let hadTap = eventTap != nil
        isPressed = false

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
        guard keyCode == Self.shortcutKeyCode else {
            return Unmanaged.passUnretained(event)
        }

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

            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 || isPressed {
                Diagnostics.record("Hotkey", "Control+Space repeat suppressed")
                return nil
            }

            isPressed = true
            Diagnostics.record("Hotkey", "Control+Space keyDown accepted")
            onPress()
            return nil

        case .keyUp:
            guard isPressed else {
                if event.flags.contains(.maskControl) {
                    Diagnostics.record("Hotkey", "Space keyUp observed without an owned hold", level: .warning)
                }
                return Unmanaged.passUnretained(event)
            }

            isPressed = false
            Diagnostics.record("Hotkey", "Control+Space keyUp accepted; ending hold")
            onRelease()
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
