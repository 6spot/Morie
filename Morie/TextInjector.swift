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
            case .noTargetApplication:
                "The original target application is unavailable. The transcript was copied to the clipboard."
            case .focusRestoreFailed:
                "Could not restore focus to the original application. The transcript was copied to the clipboard."
            case .pasteFailed:
                "Could not inject the transcript. The transcript was left on the clipboard."
            }
        }
    }

    private static let syntheticInputEventMarker = Int64.random(in: 1...Int64.max)

    static func markAsSyntheticInput(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticInputEventMarker)
    }

    static func isSyntheticInput(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticInputEventMarker
    }

    @MainActor
    func deliver(_ text: String, to application: NSRunningApplication?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Diagnostics.record("Delivery", "deliver() received empty text; returning", level: .warning)
            return
        }

        guard let application,
              !application.isTerminated,
              application.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            Diagnostics.record("Delivery", "Target application missing/terminated/self; preserving transcript on clipboard", level: .error)
            copyToClipboard(text)
            throw InjectionError.noTargetApplication
        }

        let targetName = application.localizedName ?? "unknown"
        let targetBundle = application.bundleIdentifier ?? "unknown"
        Diagnostics.record("Delivery", "Restoring target application \(targetName) (\(targetBundle))")

        let activated = application.activate(options: [.activateIgnoringOtherApps])
        Diagnostics.record("Delivery", "Target activation returned \(activated)")
        guard activated else {
            copyToClipboard(text)
            throw InjectionError.focusRestoreFailed
        }

        try await Task.sleep(for: .milliseconds(100))
        Diagnostics.record("Delivery", "Focus handoff grace period completed")

        if setSelectedTextWithAccessibility(text) {
            Diagnostics.record("Delivery", "Accessibility selected-text injection succeeded")
            return
        }

        Diagnostics.record("Delivery", "Accessibility injection unavailable/failed; using clipboard Cmd+V fallback", level: .warning)
        guard await pasteThroughClipboard(text) else {
            copyToClipboard(text)
            Diagnostics.record("Delivery", "Clipboard Cmd+V fallback failed; transcript left on clipboard", level: .error)
            throw InjectionError.pasteFailed
        }

        Diagnostics.record("Delivery", "Clipboard Cmd+V fallback dispatched")
    }

    private func setSelectedTextWithAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.20)

        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )

        guard focusResult == .success, let focused else {
            Diagnostics.record(
                "Delivery",
                "Could not resolve focused AX element; result=\(String(describing: focusResult))",
                level: .warning
            )
            return false
        }

        let element = unsafeDowncast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.20)

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if setResult != .success {
            Diagnostics.record(
                "Delivery",
                "AX selected-text write failed; result=\(String(describing: setResult))",
                level: .warning
            )
        }

        return setResult == .success
    }

    @MainActor
    private func pasteThroughClipboard(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        Diagnostics.record("Clipboard", "Captured restorable clipboard snapshot; items=\(snapshot.itemCount)")

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Diagnostics.record("Clipboard", "Failed to write transcript to pasteboard", level: .error)
            return false
        }
        let transcriptChangeCount = pasteboard.changeCount
        Diagnostics.record("Clipboard", "Temporary transcript written; changeCount=\(transcriptChangeCount)")

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            Diagnostics.record("Delivery", "Could not create synthetic Cmd+V events", level: .error)
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        Self.markAsSyntheticInput(keyDown)
        Self.markAsSyntheticInput(keyUp)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        Diagnostics.record("Delivery", "Synthetic Cmd+V posted")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            let restored = snapshot.restore(to: pasteboard, expectedChangeCount: transcriptChangeCount)
            if restored {
                Diagnostics.record("Clipboard", "Previous clipboard restored")
            } else {
                Diagnostics.record(
                    "Clipboard",
                    "Previous clipboard not restored because clipboard changed or snapshot was empty",
                    level: .warning
                )
            }
        }

        return true
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Diagnostics.record("Clipboard", "Transcript preserved on clipboard; characters=\(text.count)")
    }
}

private struct ClipboardSnapshot: Sendable {
    private static let safeTypes: Set<String> = [
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.URL.rawValue,
        NSPasteboard.PasteboardType.html.rawValue,
        "public.utf8-plain-text",
        "public.utf16-plain-text",
        "public.url",
    ]

    struct Item: Sendable {
        let values: [String: Data]
    }

    let items: [Item]

    var itemCount: Int { items.count }

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { pasteboardItem -> Item? in
            var values: [String: Data] = [:]

            for type in pasteboardItem.types where safeTypes.contains(type.rawValue) {
                if let data = pasteboardItem.data(forType: type) {
                    values[type.rawValue] = data
                }
            }

            return values.isEmpty ? nil : Item(values: values)
        }

        return ClipboardSnapshot(items: items)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard, expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            return false
        }

        guard !items.isEmpty else { return false }

        pasteboard.clearContents()
        let restored = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (rawType, data) in item.values {
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return pasteboardItem
        }

        return pasteboard.writeObjects(restored)
    }
}
