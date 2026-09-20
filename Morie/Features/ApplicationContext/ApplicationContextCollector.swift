import ApplicationServices
import Foundation

/// Captures a bounded, runtime-only snapshot of the user's current editing
/// environment through macOS Accessibility.
///
/// Accessibility calls are blocking cross-process IPC, so the collector owns a
/// dedicated actor executor and applies a short native messaging timeout to
/// every AX element it touches. The collector is deliberately generic: no
/// application-specific adapters, no screen capture, and no OCR.
actor ApplicationContextCollector {
    private enum Limit {
        static let selectedCharacters = 2_000
        static let focusedCharacters = 3_000
        static let nearbyCharacters = 6_000
        static let ancestorDepth = 6
        static let nearbyNodes = 48
        static let siblingRadius = 4
        static let childrenPerNode = 12
        static let messagingTimeout: Float = 0.05
    }

    func capture(
        _ request: ApplicationContextCaptureRequest
    ) -> ApplicationContextSnapshot {
        guard !Task.isCancelled, AXIsProcessTrusted() else {
            return emptySnapshot(for: request)
        }

        let applicationElement = AXUIElementCreateApplication(
            pid_t(request.processIdentifier)
        )
        configureTimeout(applicationElement)

        guard let focusedElement = copyElement(
            kAXFocusedUIElementAttribute,
            from: applicationElement
        ),
        !Task.isCancelled,
        !isSecureTextElement(focusedElement)
        else {
            return emptySnapshot(for: request)
        }

        var actualPID: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &actualPID) == .success,
              actualPID == pid_t(request.processIdentifier)
        else {
            return emptySnapshot(for: request)
        }

        let selectedText = boundedText(
            textAttribute(kAXSelectedTextAttribute, from: focusedElement),
            limit: Limit.selectedCharacters
        )
        let focusedText = boundedText(
            textAttribute(kAXValueAttribute, from: focusedElement),
            limit: Limit.focusedCharacters
        )
        let nearbyText = collectNearbyText(
            around: focusedElement,
            excluding: [selectedText, focusedText].compactMap { $0 }
        )

        return ApplicationContextSnapshot(
            application: request.application,
            selectedText: selectedText,
            focusedText: focusedText,
            nearbyText: nearbyText,
            capturedAt: request.capturedAt
        )
    }

    private func emptySnapshot(
        for request: ApplicationContextCaptureRequest
    ) -> ApplicationContextSnapshot {
        ApplicationContextSnapshot(
            application: request.application,
            selectedText: nil,
            focusedText: nil,
            nearbyText: nil,
            capturedAt: request.capturedAt
        )
    }

    private func collectNearbyText(
        around focusedElement: AXUIElement,
        excluding excludedText: [String]
    ) -> String? {
        var chunks: [String] = []
        var seen = Set(
            excludedText
                .map(normalizedText)
                .filter { !$0.isEmpty }
        )
        var remainingNodes = Limit.nearbyNodes
        var remainingCharacters = Limit.nearbyCharacters
        var current = focusedElement

        for _ in 0..<Limit.ancestorDepth {
            guard !Task.isCancelled,
                  remainingNodes > 0,
                  remainingCharacters > 0,
                  let parent = copyElement(kAXParentAttribute, from: current)
            else {
                break
            }

            appendOwnText(
                from: parent,
                chunks: &chunks,
                seen: &seen,
                remainingCharacters: &remainingCharacters
            )

            let siblings = childElements(of: parent)
            if let currentIndex = siblings.firstIndex(where: {
                CFEqual($0, current)
            }) {
                for offset in proximityOffsets(radius: Limit.siblingRadius) {
                    guard !Task.isCancelled else { break }
                    let index = currentIndex + offset
                    guard siblings.indices.contains(index) else { continue }
                    collectSubtreeText(
                        from: siblings[index],
                        chunks: &chunks,
                        seen: &seen,
                        remainingNodes: &remainingNodes,
                        remainingCharacters: &remainingCharacters
                    )
                    if remainingNodes == 0 || remainingCharacters == 0 {
                        break
                    }
                }
            }

            current = parent
        }

        guard !chunks.isEmpty else { return nil }
        return chunks.joined(separator: "\n")
    }

    private func collectSubtreeText(
        from root: AXUIElement,
        chunks: inout [String],
        seen: inout Set<String>,
        remainingNodes: inout Int,
        remainingCharacters: inout Int
    ) {
        var queue: [AXUIElement] = [root]
        var index = 0

        while !Task.isCancelled,
              index < queue.count,
              remainingNodes > 0,
              remainingCharacters > 0 {
            let element = queue[index]
            index += 1
            remainingNodes -= 1

            if isSecureTextElement(element) {
                continue
            }

            appendOwnText(
                from: element,
                chunks: &chunks,
                seen: &seen,
                remainingCharacters: &remainingCharacters
            )

            let children = childElements(of: element)
            if !children.isEmpty {
                queue.append(
                    contentsOf: children.prefix(Limit.childrenPerNode)
                )
            }
        }
    }

    private func appendOwnText(
        from element: AXUIElement,
        chunks: inout [String],
        seen: inout Set<String>,
        remainingCharacters: inout Int
    ) {
        guard !Task.isCancelled, remainingCharacters > 0 else { return }

        let candidates = [
            textAttribute(kAXTitleAttribute, from: element),
            textAttribute(kAXDescriptionAttribute, from: element),
            textAttribute(kAXValueAttribute, from: element),
        ]

        for candidate in candidates {
            guard !Task.isCancelled,
                  remainingCharacters > 0,
                  let candidate,
                  !candidate.isEmpty
            else {
                continue
            }

            let normalized = normalizedText(candidate)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                continue
            }

            let piece = String(candidate.prefix(remainingCharacters))
            guard !piece.isEmpty else { continue }
            chunks.append(piece)
            remainingCharacters -= piece.count
        }
    }

    private func proximityOffsets(radius: Int) -> [Int] {
        guard radius > 0 else { return [] }
        return (1...radius).flatMap { [-$0, $0] }
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        guard !Task.isCancelled,
              let value = copyAttribute(kAXChildrenAttribute, from: element),
              let children = value as? [AXUIElement]
        else {
            return []
        }
        for child in children.prefix(Limit.childrenPerNode) {
            configureTimeout(child)
        }
        return children
    }

    private func copyElement(
        _ attribute: CFString,
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
        _ attribute: CFString,
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
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        guard !Task.isCancelled else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        guard let value = textAttribute(kAXSubroleAttribute, from: element) else {
            return false
        }
        return value == (kAXSecureTextFieldSubrole as String)
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

    private func normalizedText(_ text: String) -> String {
        text
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
