import AppKit
import Foundation

struct TextInjector {
    enum InjectionError: LocalizedError {
        case noTargetApplication
        case targetWindowClosed
        case focusRestoreFailed
        case pasteFailed

        var errorDescription: String? {
            switch self {
            case .noTargetApplication:
                "The original target application is unavailable. The transcript was copied to the clipboard."
            case .targetWindowClosed:
                "The original input window was closed. The transcript was copied to the clipboard."
            case .focusRestoreFailed:
                "Could not restore focus to the original application. The transcript was copied to the clipboard."
            case .pasteFailed:
                "Could not inject the transcript. The transcript was left on the clipboard."
            }
        }
    }

    private static let syntheticInputEventMarker = Int64.random(in: 1...Int64.max)
    private static let focusHandoffDelay: Duration = .milliseconds(100)
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

    @MainActor
    static func frontmostWindowNumber(for application: NSRunningApplication?) -> CGWindowID? {
        guard let application,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[CFString: Any]]
        else { return nil }

        return windows.first { window in
            let ownerPID = window[kCGWindowOwnerPID] as? NSNumber
            let layer = window[kCGWindowLayer] as? NSNumber
            return ownerPID?.int32Value == application.processIdentifier
                && layer?.intValue == 0
        }
        .flatMap { ($0[kCGWindowNumber] as? NSNumber)?.uint32Value }
    }

    @MainActor
    func deliver(
        _ text: String,
        to application: NSRunningApplication?,
        originalWindowNumber: CGWindowID?
    ) async throws {
        try Task.checkCancellation()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Diagnostics.record("Delivery", "deliver() received empty text; returning", level: .warning)
            return
        }

        guard let application,
              !application.isTerminated,
              application.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            Diagnostics.record(
                "Delivery",
                "Target application missing/terminated/self; preserving transcript on clipboard",
                level: .error
            )
            copyToClipboard(text)
            throw InjectionError.noTargetApplication
        }

        let targetName = application.localizedName ?? "unknown"
        let targetBundle = application.bundleIdentifier ?? "unknown"

        if let originalWindowNumber, !Self.windowExists(originalWindowNumber) {
            Diagnostics.record(
                "Delivery",
                "Original target window \(originalWindowNumber) no longer exists; preserving transcript on clipboard",
                level: .error
            )
            copyToClipboard(text)
            throw InjectionError.targetWindowClosed
        }

        Diagnostics.record("Delivery", "Restoring target application \(targetName) (\(targetBundle))")

        let activated = application.activate()
        Diagnostics.record("Delivery", "Target activation returned \(activated)")
        guard activated else {
            copyToClipboard(text)
            throw InjectionError.focusRestoreFailed
        }

        try await Task.sleep(for: Self.focusHandoffDelay)
        try Task.checkCancellation()
        Diagnostics.record("Delivery", "Focus handoff grace period completed")

        if let originalWindowNumber, !Self.windowExists(originalWindowNumber) {
            Diagnostics.record(
                "Delivery",
                "Original target window \(originalWindowNumber) closed during focus handoff; preserving transcript on clipboard",
                level: .error
            )
            copyToClipboard(text)
            throw InjectionError.targetWindowClosed
        }

        // Morie intentionally uses one generic delivery mechanism for current-app
        // insertion. Direct AX writes can report success while some editors ignore
        // the mutation, which makes success impossible to trust uniformly. A
        // temporary clipboard value plus a synthetic Cmd+V exercises the same
        // standard paste path the target application already supports for users.
        Diagnostics.record("Delivery", "Using universal clipboard Cmd+V delivery")

        guard pasteThroughClipboard(text) else {
            copyToClipboard(text)
            Diagnostics.record(
                "Delivery",
                "Clipboard Cmd+V delivery failed; transcript left on clipboard",
                level: .error
            )
            throw InjectionError.pasteFailed
        }

        Diagnostics.record("Delivery", "Clipboard Cmd+V delivery dispatched")
    }

    private static func windowExists(_ windowNumber: CGWindowID) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowNumber
        ) as? [[CFString: Any]] else { return false }

        return windows.contains { window in
            (window[kCGWindowNumber] as? NSNumber)?.uint32Value == windowNumber
        }
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
