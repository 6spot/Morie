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

    /// Type4Me proved that synthetic delivery events need an identity so the
    /// hotkey path can ignore Morie's own Cmd+V events when that path moves to
    /// a CGEvent tap. Keep this marker process-local and randomized.
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
        guard !trimmed.isEmpty else { return }

        guard let application,
              !application.isTerminated,
              application.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            copyToClipboard(text)
            throw InjectionError.noTargetApplication
        }

        let activated = application.activate(options: [.activateIgnoringOtherApps])
        guard activated else {
            copyToClipboard(text)
            throw InjectionError.focusRestoreFailed
        }

        // Focus restoration is asynchronous across applications. Keep this
        // short here; the compatibility matrix will determine whether a
        // bounded target-aware retry is required for specific app classes.
        try await Task.sleep(for: .milliseconds(100))

        if setSelectedTextWithAccessibility(text) {
            return
        }

        guard await pasteThroughClipboard(text) else {
            // Never lose the result simply because synthetic paste creation
            // failed. Preserve it as a normal clipboard value.
            copyToClipboard(text)
            throw InjectionError.pasteFailed
        }
    }

    private func setSelectedTextWithAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.20)

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

        let element = unsafeDowncast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.20)

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    @MainActor
    private func pasteThroughClipboard(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        let transcriptChangeCount = pasteboard.changeCount

        // Give native/Electron editors a short opportunity to observe the new
        // pasteboard value before Cmd+V. This value remains part of the real-app
        // compatibility test rather than being treated as universally correct.
        try? await Task.sleep(for: .milliseconds(50))

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        Self.markAsSyntheticInput(keyDown)
        Self.markAsSyntheticInput(keyUp)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Type4Me found Electron-family apps may read the clipboard late. More
        // importantly, only restore if nobody changed the clipboard after Morie
        // wrote the transcript; otherwise restoration would destroy user data.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            snapshot.restore(to: pasteboard, expectedChangeCount: transcriptChangeCount)
        }

        return true
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct ClipboardSnapshot: Sendable {
    /// Capture only text-like pasteboard representations. Reading arbitrary
    /// binary/lazy pasteboard providers can block the app and isn't necessary
    /// for Morie's transient text-injection fallback.
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
    func restore(to pasteboard: NSPasteboard, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else {
            // Someone changed the clipboard after Morie's transient write.
            // Their newer clipboard content always wins.
            return
        }

        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (rawType, data) in item.values {
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return pasteboardItem
        }

        pasteboard.writeObjects(restored)
    }
}
