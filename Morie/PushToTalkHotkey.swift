import AppKit

@MainActor
final class PushToTalkHotkey {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPressed = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        install()
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isPressed = false
    }

    private func install() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == 49 else { return } // Space
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control) else {
            if event.type == .keyUp, isPressed {
                isPressed = false
                onRelease()
            }
            return
        }

        switch event.type {
        case .keyDown where !event.isARepeat && !isPressed:
            isPressed = true
            onPress()
        case .keyUp where isPressed:
            isPressed = false
            onRelease()
        default:
            break
        }
    }
}
