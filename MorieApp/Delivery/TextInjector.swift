import AppKit
import ApplicationServices
import Carbon
import Foundation

struct TextInjector {
    enum Method: String, Sendable {
        case accessibilitySelectedText
        case clipboardPaste
    }

    enum Error: LocalizedError {
        case accessibilityPermissionMissing
        case pasteboardWriteFailed
        case keyboardEventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing: "Accessibility permission is required to insert text."
            case .pasteboardWriteFailed: "Unable to write the final text to the pasteboard."
            case .keyboardEventCreationFailed: "Unable to synthesize the paste keyboard event."
            }
        }
    }

    func insert(_ text: String) throws -> Method {
        guard AXIsProcessTrusted() else { throw Error.accessibilityPermissionMissing }

        if insertThroughAccessibility(text) {
            return .accessibilitySelectedText
        }

        try paste(text)
        return .clipboardPaste
    }

    private func insertThroughAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue
        else { return false }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        let result = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    private func paste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw Error.pasteboardWriteFailed
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { throw Error.keyboardEventCreationFailed }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            snapshot.restore(to: pasteboard)
        }
    }
}

private struct PasteboardSnapshot: @unchecked Sendable {
    struct Item: Sendable {
        let values: [String: Data]
    }

    let items: [Item]

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { source in
            var values: [String: Data] = [:]
            for type in source.types {
                if let data = source.data(forType: type) {
                    values[type.rawValue] = data
                }
            }
            return Item(values: values)
        }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.map { saved in
            let item = NSPasteboardItem()
            for (rawType, data) in saved.values {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
