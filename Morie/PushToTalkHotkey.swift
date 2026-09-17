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
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
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
            throw StartError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            invalidate()
            throw StartError.eventTapCreationFailed
        }
    }

    func invalidate() {
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
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverEventTapIfPossible()
            return Unmanaged.passUnretained(event)
        }

        // Morie-generated delivery keystrokes are never hotkey input.
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
                return Unmanaged.passUnretained(event)
            }

            // Consume repeat events but never dispatch another recording start.
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 || isPressed {
                return nil
            }

            isPressed = true
            onPress()
            return nil

        case .keyUp:
            // Once Morie owns the hold, release must terminate it even if the
            // user released Control before releasing Space.
            guard isPressed else {
                return Unmanaged.passUnretained(event)
            }

            isPressed = false
            onRelease()
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func recoverEventTapIfPossible() {
        guard let tap = eventTap else { return }

        guard AXIsProcessTrusted() else {
            invalidate()
            onUnavailable(StartError.accessibilityUnavailable)
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            invalidate()
            onUnavailable(StartError.eventTapCreationFailed)
            return
        }
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

    // The tap source is installed on the main run loop. Keeping all mutable
    // hotkey state on that run loop gives Morie deterministic press/release
    // ownership without a generalized synchronization layer.
    let hotkey = Unmanaged<PushToTalkHotkey>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    return hotkey.handle(type: type, event: event)
}
