import AppKit
import ApplicationServices
import Foundation

struct TextInjector {
    enum InjectionError: LocalizedError {
        case noTargetApplication
        case focusRestoreFailed
        case pasteFailed

        var errorDescription: String? {
            switch self {
            case .noTargetApplication: "The original target application is no longer available."
            case .focusRestoreFailed: "Could not restore focus to the original application."
            case .pasteFailed: "Could not inject the transcribed text."
            }
        }
    }

    @MainActor
    func deliver(_ text: String, to application: NSRunningApplication?) async throws {
        guard let application, !application.isTerminated else {
            throw InjectionError.noTargetApplication
        }

        let activated = application.activate(options: [.activateIgnoringOtherApps])
        guard activated else { throw InjectionError.focusRestoreFailed }

        try await Task.sleep(for: .milliseconds(80))

        if setSelectedTextWithAccessibility(text) {
            return
        }

        guard pasteThroughClipboard(text) else {
            throw InjectionError.pasteFailed
        }
    }

    private func setSelectedTextWithAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
        let focused
        else {
            return false
        }

        let element = focused as! AXUIElement
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func pasteThroughClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let oldItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: String]? in
            var values: [NSPasteboard.PasteboardType: String] = [:]
            for type in item.types {
                if let value = item.string(forType: type) {
                    values[type] = value
                }
            }
            return values.isEmpty ? nil : values
        }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if let oldItems {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                let restored = oldItems.map { values -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, value) in values {
                        item.setString(value, forType: type)
                    }
                    return item
                }
                pasteboard.clearContents()
                pasteboard.writeObjects(restored)
            }
        }

        return true
    }
}
