import AppKit
import Foundation

struct TextInjector {
    enum InjectionError: LocalizedError {
        case noCurrentTargetApplication
        case pasteFailed

        var errorDescription: String? {
            switch self {
            case .noCurrentTargetApplication:
                "当前没有可输入的外部应用，文字已复制到剪贴板。"
            case .pasteFailed:
                "无法自动输入文字，文字已保留在剪贴板中。"
            }
        }
    }

    private static let syntheticInputEventMarker = Int64.random(in: 1...Int64.max)
    private static let clipboardRestoreDelay: Duration = .milliseconds(500)
    private static let transientPasteboardType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    static func markAsSyntheticInput(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticInputEventMarker)
    }

    static func isSyntheticInput(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticInputEventMarker
    }

    /// Interactive Morie input follows the system keyboard model: resolve the
    /// destination only when the final text is ready, never reactivate an app
    /// remembered at recording start.
    @MainActor
    func deliver(_ text: String) throws -> NSRunningApplication {
        try Task.checkCancellation()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Diagnostics.record("Delivery", "deliver() received empty text; returning current app", level: .warning)
            guard let application = NSWorkspace.shared.frontmostApplication else {
                throw InjectionError.noCurrentTargetApplication
            }
            return application
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              !application.isTerminated,
              application.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            Diagnostics.record(
                "Delivery",
                "No external frontmost application at delivery time; preserving transcript on clipboard",
                level: .error
            )
            copyToClipboard(text)
            throw InjectionError.noCurrentTargetApplication
        }

        let targetName = application.localizedName ?? "unknown"
        let targetBundle = application.bundleIdentifier ?? "unknown"
        Diagnostics.record(
            "Delivery",
            "Dispatching current-focus input to \(targetName) (\(targetBundle))"
        )

        // A temporary clipboard value plus a synthetic Cmd+V intentionally lets
        // macOS and the target application's first-responder chain decide which
        // control receives text. Accessibility is not used to prove editability.
        guard pasteThroughClipboard(text) else {
            copyToClipboard(text)
            Diagnostics.record(
                "Delivery",
                "Clipboard Cmd+V delivery failed; transcript left on clipboard",
                level: .error
            )
            throw InjectionError.pasteFailed
        }

        Diagnostics.record("Delivery", "Current-focus clipboard Cmd+V dispatched")
        return application
    }

    @MainActor
    private func pasteThroughClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        Diagnostics.record("Clipboard", "Captured restorable clipboard snapshot; items=\(snapshot.itemCount)")

        let temporaryItem = NSPasteboardItem()
        temporaryItem.setString(text, forType: .string)
        temporaryItem.setData(Data(), forType: Self.transientPasteboardType)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([temporaryItem]) else {
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
            try? await Task.sleep(for: Self.clipboardRestoreDelay)
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

        // An empty clipboard is still a valid snapshot. After a successful
        // temporary paste, clear Morie's transcript so it does not become the
        // user's new clipboard contents.
        guard !items.isEmpty else {
            pasteboard.clearContents()
            return true
        }

        pasteboard.clearContents()
        let restored = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (rawType, data) in item.values {
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            pasteboardItem.setData(
                Data(),
                forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
            )
            return pasteboardItem
        }

        return pasteboard.writeObjects(restored)
    }
}
