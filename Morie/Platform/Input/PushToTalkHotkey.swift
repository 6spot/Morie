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
        case eventTapTimedOut

        var errorDescription: String? {
            switch self {
            case .accessibilityUnavailable:
                "使用全局录音快捷键需要辅助功能权限。"
            case .eventTapCreationFailed:
                "无法启用全局录音快捷键，请在使用引导中检查权限后重试。"
            case .eventTapTimedOut:
                "键盘响应超时，Morie 已停用全局快捷键。请打开使用引导，重新检查并点击“开始使用”以恢复。"
            }
        }
    }

    private static let spaceKeyCode = CGKeyCode(49)
    private static let functionKeyCode = CGKeyCode(63)
    private static let escapeKeyCode = CGKeyCode(53)
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
    private let shortcut: CaptureShortcut

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcutPressOwned = false
    private var escapePressOwned = false
    private var cancellationEnabled = false
    private var functionKeyDown = false
    private var functionKeyUsedInChord = false

    init(
        shortcut: CaptureShortcut,
        onToggle: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUnavailable: @escaping (Error) -> Void
    ) {
        self.shortcut = shortcut
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
        Diagnostics.record("Hotkey", "Installing \(shortcut.logName) toggle event tap; accessibilityTrusted=\(trusted)")
        guard trusted else {
            throw StartError.accessibilityUnavailable
        }

        let mask = Self.mask(for: .keyDown)
            | Self.mask(for: .keyUp)
            | Self.mask(for: .flagsChanged)
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

        Diagnostics.record("Hotkey", "\(shortcut.logName) toggle event tap installed and enabled")
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
        functionKeyDown = false
        functionKeyUsedInChord = false

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
        // Fail open before interpreting or consuming any keyboard event. If
        // TCC changes while Morie is running, the system must keep the event
        // and Morie must release its tap immediately.
        guard AXIsProcessTrusted() else {
            Diagnostics.record(
                "Hotkey",
                "Accessibility trust lost during event handling; releasing event tap",
                level: .error
            )
            invalidate()
            onUnavailable(StartError.accessibilityUnavailable)
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Diagnostics.record(
                "Hotkey",
                "Event tap disabled by system; releasing tap instead of re-enabling it to protect system keyboard input",
                level: .error
            )
            invalidate()
            onUnavailable(StartError.eventTapTimedOut)
            return Unmanaged.passUnretained(event)
        }

        if TextInjector.isSyntheticInput(event) {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if shortcut == .functionKey {
            if type == .flagsChanged, keyCode == Self.functionKeyCode {
                return handleFunctionKey(event: event)
            }

            if functionKeyDown, (type == .keyDown || type == .flagsChanged) {
                functionKeyUsedInChord = true
                Diagnostics.record("Hotkey", "Fn solo candidate cancelled by keyCode=\(keyCode)")
            }
        }

        if shortcut != .functionKey, keyCode == Self.spaceKeyCode {
            return handleShortcut(type: type, event: event)
        }

        if keyCode == Self.escapeKeyCode {
            return handleEscape(type: type, event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFunctionKey(event: CGEvent) -> Unmanaged<CGEvent>? {
        let isDown = event.flags.contains(.maskSecondaryFn)

        if isDown, !functionKeyDown {
            functionKeyDown = true
            functionKeyUsedInChord = false
            Diagnostics.record("Hotkey", "Fn press began; waiting for solo release")
            return Unmanaged.passUnretained(event)
        }

        if !isDown, functionKeyDown {
            functionKeyDown = false
            let shouldToggle = !functionKeyUsedInChord
            functionKeyUsedInChord = false

            guard shouldToggle else {
                Diagnostics.record("Hotkey", "Fn release passed through because Fn was used in a chord")
                return Unmanaged.passUnretained(event)
            }

            Diagnostics.record("Hotkey", "Fn solo release accepted; toggling capture")
            DevelopmentDiagnostics.record(
                "HotkeyEvent",
                "accepted; shortcut=Fn; event=soloRelease; consumed=true"
            )
            onToggle()
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleShortcut(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            guard hasExactShortcutModifiers(event.flags) else {
                if !event.flags.intersection(Self.relevantModifiers).isEmpty {
                    Diagnostics.record(
                        "Hotkey",
                        "Space keyDown ignored because modifiers did not match \(shortcut.logName); flags=0x\(String(event.flags.rawValue, radix: 16))",
                        level: .warning
                    )
                }
                return Unmanaged.passUnretained(event)
            }

            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 || shortcutPressOwned {
                Diagnostics.record("Hotkey", "\(shortcut.logName) repeat suppressed")
                return nil
            }

            shortcutPressOwned = true
            Diagnostics.record("Hotkey", "\(shortcut.logName) keyDown accepted; toggling capture")
            DevelopmentDiagnostics.record(
                "HotkeyEvent",
                "accepted; shortcut=\(shortcut.logName); event=keyDown; consumed=true; flags=0x\(String(event.flags.rawValue, radix: 16))"
            )
            onToggle()
            return nil

        case .keyUp:
            guard shortcutPressOwned else {
                return Unmanaged.passUnretained(event)
            }

            shortcutPressOwned = false
            Diagnostics.record("Hotkey", "\(shortcut.logName) keyUp accepted; capture state unchanged")
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
            DevelopmentDiagnostics.record(
                "HotkeyEvent",
                "accepted; shortcut=Escape; event=keyDown; consumed=true; cancellationEnabled=\(cancellationEnabled)"
            )
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

    private func hasExactShortcutModifiers(_ flags: CGEventFlags) -> Bool {
        flags.intersection(Self.relevantModifiers) == shortcut.requiredModifiers
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
