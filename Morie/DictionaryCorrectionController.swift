import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

/// An opt-in, short-lived observer of a verified Morie insertion. No keyboard events or document-wide reads.
@MainActor
final class DictionaryCorrectionController {
    static let enabledDefaultsKey = "dictionaryCorrectionSuggestionsEnabled"
    private let dictionary: DictionaryStore
    private var observationTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var observationID: UUID?
    private var panel: NSPanel?
    private var suggestedWords = Set<String>()
    private var suggestedWordOrder: [String] = []
    private let maximumSuggestedWords = 256

    init(dictionary: DictionaryStore) { self.dictionary = dictionary }

    func stop() {
        observationID = nil
        observationTask?.cancel()
        observationTask = nil
        dismiss()
    }

    func observeInsertion(_ text: String, in application: NSRunningApplication?) {
        stop()
        guard let application, !application.isTerminated,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              !["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.keychainaccess"].contains(application.bundleIdentifier ?? ""),
              !(application.bundleIdentifier ?? "").localizedCaseInsensitiveContains("password"),
              (2...1_200).contains(text.utf16.count) else { return }
        let id = UUID()
        let pid = application.processIdentifier
        observationID = id
        observationTask = Task { [weak self] in
            let reader = CorrectionFieldReader()
            let deadline = ContinuousClock.now + .seconds(30)
            defer {
                if self?.observationID == id {
                    self?.observationTask = nil
                    self?.dismiss()
                }
            }
            do {
                var anchored = false
                // Wait for the actual paste to appear. Never assume an unmatched value is our insertion.
                for _ in 0..<6 {
                    try await Task.sleep(for: .milliseconds(200))
                    guard self?.observationID == id else { return }
                    if await reader.anchor(text, pid: pid) { anchored = true; break }
                }
                guard anchored else { return }
                var tracker = DictionaryCorrectionTracker(original: text)
                var offeredText: String?
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(750))
                    guard self?.observationID == id, let sample = await reader.sample(pid: pid) else { return }
                    try Task.checkCancellation()
                    if let offeredText {
                        // Editing again or leaving the field invalidates the displayed suggestion.
                        guard sample == offeredText, self?.panel != nil else { return }
                        continue
                    }
                    if let correction = tracker.observe(sample, at: Date()) {
                        self?.present(correction)
                        guard self?.panel != nil else { return }
                        offeredText = sample
                    }
                }
            } catch { }
        }
    }

    private func present(_ correction: DictionaryCorrection) {
        guard let observationID else { return }
        let key = MemoryText.normalized(correction.replacement)
        guard !suggestedWords.contains(key) else { return }
        do {
            guard try !dictionary.containsEffectiveWord(correction.replacement) else { return }
        } catch { return }
        suggestedWords.insert(key)
        suggestedWordOrder.append(key)
        if suggestedWordOrder.count > maximumSuggestedWords {
            let removed = suggestedWordOrder.removeFirst()
            suggestedWords.remove(removed)
        }
        let content = DictionaryCorrectionPrompt(correction: correction, save: { [weak self] in
            guard let self else { return }
            // Save the same single word as the dictionary editor.
            try self.dictionary.create(DictionaryDraft(name: correction.replacement), source: .correction)
            self.dismiss()
        }, dismiss: { [weak self] in self?.dismiss() })
            .frame(width: 370)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                guard self?.observationID == observationID else { return }
                self?.panel?.setContentSize(size)
            }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 180),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "加入字典"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: content)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.minY + 24))
        }
        self.panel = panel
        panel.orderFrontRegardless()
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)); self?.dismiss() } catch { }
        }
    }

    private func dismiss() {
        expiryTask?.cancel()
        expiryTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

struct DictionaryCorrectionPrompt: View {
    let correction: DictionaryCorrection
    let save: () throws -> Void
    let dismiss: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("将“\(correction.replacement)”加入字典？").font(.headline)
            Text("\(correction.original) → \(correction.replacement)").textSelection(.enabled)
            Text("以后识别语音时，将这个词语作为拼写提示。").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("暂不添加", action: dismiss)
                Button("加入字典") {
                    do { try save() }
                    catch { self.error = "无法保存词语，请重试。" }
                }
            }
        }
        .padding(20)
    }
}

/// Blocking Accessibility IPC stays off the main actor and each message has a short native deadline.
private actor CorrectionFieldReader {
    private struct Field {
        let element: AXUIElement
        let start: Int
        let insertedLength: Int
        let totalLength: Int
    }
    private var field: Field?

    func anchor(_ inserted: String, pid: pid_t) -> Bool {
        guard !Task.isCancelled, let element = focusedTextField(pid: pid),
              let selection = selectedRange(element), selection.length == 0,
              let total = numberOfCharacters(element), selection.location <= total,
              selection.location >= inserted.utf16.count else { return false }
        let start = selection.location - inserted.utf16.count
        guard string(element, range: CFRange(location: start, length: inserted.utf16.count)) == inserted,
              !Task.isCancelled else { return false }
        field = Field(element: element, start: start, insertedLength: inserted.utf16.count, totalLength: total)
        return true
    }

    func sample(pid: pid_t) -> String? {
        guard !Task.isCancelled, let field, let focused = focusedTextField(pid: pid), CFEqual(focused, field.element),
              let total = numberOfCharacters(field.element), abs(total - field.totalLength) <= 64 else { self.field = nil; return nil }
        let length = field.insertedLength + total - field.totalLength
        guard length > 0, length <= 1_264, field.start + length <= total,
              let selection = selectedRange(field.element), selection.location >= field.start,
              selection.location <= field.start + length,
              selection.length <= field.start + length - selection.location,
              let text = string(field.element, range: CFRange(location: field.start, length: length)),
              text.utf16.count == length else { self.field = nil; return nil }
        return text
    }

    private func focusedTextField(pid: pid_t) -> AXUIElement? {
        guard !Task.isCancelled, AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let value = attribute(system, kAXFocusedUIElementAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        var actualPID: pid_t = 0
        guard AXUIElementGetPid(element, &actualPID) == .success, actualPID == pid,
              let role = attribute(element, kAXRoleAttribute as CFString) as? String,
              [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(role),
              (attribute(element, kAXSubroleAttribute as CFString) as? String) != kAXSecureTextFieldSubrole as String,
              !Task.isCancelled else { return nil }
        return element
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        guard !Task.isCancelled else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    private func numberOfCharacters(_ element: AXUIElement) -> Int? {
        guard let count = attribute(element, kAXNumberOfCharactersAttribute as CFString) as? NSNumber,
              (0...2_000_000).contains(count.intValue) else { return nil }
        return count.intValue
    }

    private func string(_ element: AXUIElement, range: CFRange) -> String? {
        guard !Task.isCancelled else { return nil }
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
              !Task.isCancelled else { return nil }
        return value as? String
    }
}
