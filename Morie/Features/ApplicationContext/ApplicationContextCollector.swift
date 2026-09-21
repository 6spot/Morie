@preconcurrency import ApplicationServices
import Carbon
import Foundation

/// Captures a bounded, runtime-only snapshot of the text control that owns the
/// insertion caret when a Capture starts.
///
/// The collector intentionally does not walk parents, siblings or descendant
/// UI trees. Surrounding application chrome is not document context. If the
/// focused element cannot expose a trustworthy caret/text range, Morie returns
/// no cursor context rather than substituting unrelated UI text.
actor ApplicationContextCollector {
    private enum Limit {
        static let selectedCharacters = 2_000
        static let cursorCharacters = 600
        static let fullTextMaxUTF16 = 20_000
        static let messagingTimeout: Float = 0.05
    }

    private struct CursorRead {
        let text: String?
        let source: String
        let caretUTF16: Int?
        let documentUTF16: Int?
        let reason: String?
    }

    func capture(
        _ request: ApplicationContextCaptureRequest,
        captureID: UUID? = nil
    ) -> ApplicationContextSnapshot {
        let trusted = AXIsProcessTrusted()
        let secureInput = IsSecureEventInputEnabled()
        DevelopmentDiagnostics.record(
            "AX",
            captureID: captureID,
            "start; app=\(request.application.name ?? "unknown"); bundle=\(request.application.bundleIdentifier ?? "unknown"); pid=\(request.processIdentifier); trusted=\(trusted); secureInput=\(secureInput)"
        )
        guard !Task.isCancelled, trusted, !secureInput else {
            DevelopmentDiagnostics.record(
                "AX",
                captureID: captureID,
                level: .warning,
                "empty; reason=\(Task.isCancelled ? "cancelled" : (!trusted ? "notTrusted" : "secureEventInput"))"
            )
            return emptySnapshot(for: request)
        }

        let applicationElement = AXUIElementCreateApplication(
            pid_t(request.processIdentifier)
        )
        configureTimeout(applicationElement)

        guard let focusedElement = copyElement(
            kAXFocusedUIElementAttribute,
            from: applicationElement
        ) else {
            DevelopmentDiagnostics.record(
                "AX",
                captureID: captureID,
                level: .warning,
                "empty; reason=noFocusedUIElement"
            )
            return emptySnapshot(for: request)
        }
        guard !Task.isCancelled else {
            DevelopmentDiagnostics.record(
                "AX",
                captureID: captureID,
                level: .warning,
                "empty; reason=cancelledAfterFocus"
            )
            return emptySnapshot(for: request)
        }
        guard !isSecureTextElement(focusedElement) else {
            DevelopmentDiagnostics.record(
                "AX",
                captureID: captureID,
                level: .warning,
                "empty; reason=secureTextElement"
            )
            return emptySnapshot(for: request)
        }

        let role = textAttribute(kAXRoleAttribute, from: focusedElement)
        let subrole = textAttribute(kAXSubroleAttribute, from: focusedElement)
        DevelopmentDiagnostics.record(
            "AX",
            captureID: captureID,
            "focusedRole=\(role ?? "unknown"); focusedSubrole=\(subrole ?? "none"); title=\(textAttribute(kAXTitleAttribute, from: focusedElement) ?? "none")"
        )

        var actualPID: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &actualPID) == .success,
              actualPID == pid_t(request.processIdentifier)
        else {
            DevelopmentDiagnostics.record(
                "AX",
                captureID: captureID,
                level: .warning,
                "empty; reason=pidMismatch; actualPID=\(actualPID); expectedPID=\(request.processIdentifier)"
            )
            return emptySnapshot(for: request)
        }

        let selectedText = boundedText(
            textAttribute(kAXSelectedTextAttribute, from: focusedElement),
            limit: Limit.selectedCharacters
        )
        let cursor = readCursorContext(from: focusedElement)

        DevelopmentDiagnostics.record(
            "AX",
            captureID: captureID,
            "complete; selectedCharacters=\(selectedText?.count ?? 0); cursorCharacters=\(cursor.text?.count ?? 0); cursorSource=\(cursor.source); caretUTF16=\(cursor.caretUTF16.map(String.init) ?? "none"); documentUTF16=\(cursor.documentUTF16.map(String.init) ?? "none"); cursorBudget=\(Limit.cursorCharacters); cursorReason=\(cursor.reason ?? "none"); treeTraversal=false"
        )

        return ApplicationContextSnapshot(
            application: request.application,
            selectedText: selectedText,
            cursorText: cursor.text,
            capturedAt: request.capturedAt
        )
    }

    private func emptySnapshot(
        for request: ApplicationContextCaptureRequest
    ) -> ApplicationContextSnapshot {
        ApplicationContextSnapshot(
            application: request.application,
            selectedText: nil,
            cursorText: nil,
            capturedAt: request.capturedAt
        )
    }

    /// OpenLess-style host-document boundary:
    /// - require a real AXSelectedTextRange/caret;
    /// - read only the focused element's own document text;
    /// - cap the window around the caret;
    /// - fail closed when the element cannot expose a trustworthy document.
    private func readCursorContext(
        from focusedElement: AXUIElement
    ) -> CursorRead {
        guard !Task.isCancelled else {
            return CursorRead(
                text: nil,
                source: "none",
                caretUTF16: nil,
                documentUTF16: nil,
                reason: "cancelled"
            )
        }
        guard let selectedRange = selectedTextRange(from: focusedElement) else {
            return CursorRead(
                text: nil,
                source: "none",
                caretUTF16: nil,
                documentUTF16: nil,
                reason: "selectedTextRangeUnavailable"
            )
        }
        guard selectedRange.location >= 0 else {
            return CursorRead(
                text: nil,
                source: "none",
                caretUTF16: nil,
                documentUTF16: nil,
                reason: "caretNotFound"
            )
        }
        guard let totalUTF16 = integerAttribute(
            kAXNumberOfCharactersAttribute,
            from: focusedElement
        ) else {
            return CursorRead(
                text: nil,
                source: "none",
                caretUTF16: selectedRange.location,
                documentUTF16: nil,
                reason: "numberOfCharactersUnavailable"
            )
        }

        let caretUTF16 = min(selectedRange.location, totalUTF16)

        if totalUTF16 <= Limit.fullTextMaxUTF16,
           let fullText = textAttribute(kAXValueAttribute, from: focusedElement) {
            let text = ApplicationContextCursorWindow.window(
                in: fullText,
                cursorUTF16: caretUTF16,
                budget: Limit.cursorCharacters
            )
            return CursorRead(
                text: cleanedText(text),
                source: "AXValue",
                caretUTF16: caretUTF16,
                documentUTF16: totalUTF16,
                reason: nil
            )
        }

        // For large documents, or controls that do not expose AXValue, ask the
        // focused element for only a bounded UTF-16 range around the caret.
        // Twice the character budget is a safe UTF-16 envelope for emoji and
        // other surrogate pairs; the returned string is then cropped to the
        // exact character budget.
        let span = ApplicationContextCursorWindow.plan(
            length: totalUTF16,
            cursor: caretUTF16,
            budget: Limit.cursorCharacters * 2
        )
        guard span.length > 0,
              let rangeText = stringForRange(
                from: focusedElement,
                location: span.start,
                length: span.length
              )
        else {
            return CursorRead(
                text: nil,
                source: "none",
                caretUTF16: caretUTF16,
                documentUTF16: totalUTF16,
                reason: "stringForRangeUnavailable"
            )
        }

        let text = ApplicationContextCursorWindow.window(
            in: rangeText,
            cursorUTF16: span.cursorInWindow,
            budget: Limit.cursorCharacters
        )
        return CursorRead(
            text: cleanedText(text),
            source: "AXStringForRange",
            caretUTF16: caretUTF16,
            documentUTF16: totalUTF16,
            reason: nil
        )
    }

    private func selectedTextRange(
        from element: AXUIElement
    ) -> CFRange? {
        guard !Task.isCancelled,
              let value = copyAttribute(
                kAXSelectedTextRangeAttribute,
                from: element
              ),
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func integerAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> Int? {
        guard !Task.isCancelled,
              let value = copyAttribute(attribute, from: element)
        else {
            return nil
        }
        if let number = value as? NSNumber {
            let integer = number.intValue
            return integer >= 0 ? integer : nil
        }
        return nil
    }

    private func stringForRange(
        from element: AXUIElement,
        location: Int,
        length: Int
    ) -> String? {
        guard !Task.isCancelled,
              location >= 0,
              length >= 0
        else {
            return nil
        }

        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter,
            &value
        ) == .success,
              let value
        else {
            return nil
        }

        if let string = value as? String {
            return cleanedText(string)
        }
        if let attributed = value as? NSAttributedString {
            return cleanedText(attributed.string)
        }
        return nil
    }

    private func copyElement(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard !Task.isCancelled,
              let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let child = value as! AXUIElement
        configureTimeout(child)
        return child
    }

    private func textAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        guard !Task.isCancelled,
              let value = copyAttribute(attribute, from: element)
        else {
            return nil
        }

        if let string = value as? String {
            return cleanedText(string)
        }
        if let attributed = value as? NSAttributedString {
            return cleanedText(attributed.string)
        }
        return nil
    }

    private func copyAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        guard !Task.isCancelled else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        let role = textAttribute(kAXRoleAttribute, from: element)
        let subrole = textAttribute(kAXSubroleAttribute, from: element)
        return role == kAXSecureTextFieldSubrole
            || subrole == kAXSecureTextFieldSubrole
    }

    private func configureTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, Limit.messagingTimeout)
    }

    private func boundedText(_ text: String?, limit: Int) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(limit))
    }

    private func cleanedText(_ text: String) -> String? {
        let value = text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// Pure cursor-window planner kept separate from AX so the most important
/// boundary can be regression-tested without Accessibility permissions.
///
/// The budget follows OpenLess' host-document split: prefer roughly 80% before
/// the caret and 20% after it, then let either side consume unused capacity.
enum ApplicationContextCursorWindow {
    struct Span: Equatable {
        let start: Int
        let length: Int
        let cursorInWindow: Int
    }

    static func plan(
        length: Int,
        cursor: Int,
        budget: Int
    ) -> Span {
        let safeLength = max(0, length)
        let safeCursor = min(max(0, cursor), safeLength)
        guard budget > 0 else {
            return Span(
                start: safeCursor,
                length: 0,
                cursorInWindow: 0
            )
        }

        let before = min(safeCursor, budget * 4 / 5)
        let after = min(safeLength - safeCursor, budget - before)
        let refilledBefore = min(safeCursor, budget - after)
        return Span(
            start: safeCursor - refilledBefore,
            length: refilledBefore + after,
            cursorInWindow: refilledBefore
        )
    }

    static func window(
        in text: String,
        cursorUTF16: Int,
        budget: Int
    ) -> String {
        let cursor = characterOffset(
            in: text,
            utf16Offset: cursorUTF16
        )
        let span = plan(
            length: text.count,
            cursor: cursor,
            budget: budget
        )
        return String(
            text.dropFirst(span.start).prefix(span.length)
        )
    }

    static func characterOffset(
        in text: String,
        utf16Offset: Int
    ) -> Int {
        let target = max(0, utf16Offset)
        var units = 0
        for (index, character) in text.enumerated() {
            if units >= target {
                return index
            }
            units += character.utf16.count
        }
        return text.count
    }
}
