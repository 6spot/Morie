import Foundation

struct DictionaryCorrection: Equatable, Identifiable, Sendable {
    var id = UUID()
    let original: String
    let replacement: String
}

enum DictionaryCorrectionDetector {
    /// Inspect only an already verified Morie insertion. A suggestion never writes a replacement rule.
    static func detect(original: String, edited: String) -> DictionaryCorrection? {
        guard original != edited, original.utf16.count <= 1_200, edited.utf16.count <= 1_264 else { return nil }
        let before = Array(original)
        let after = Array(edited)
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
        let oldWords = wordOffsets(in: original)
        let newWords = wordOffsets(in: edited)
        // Expand both sides together: shared letters may belong to different word boundaries
        // ("more e" → "Morie", "Open AI" → "OpenAI", or "Claud" → "Claude").
        var changed = true
        while changed {
            let previous = (prefix, suffix)
            for (words, count) in [(oldWords, before.count), (newWords, after.count)] {
                if let word = words.first(where: { $0.lowerBound < prefix && prefix < $0.upperBound }) {
                    prefix = word.lowerBound
                }
                let end = count - suffix
                if let word = words.first(where: { $0.lowerBound < end && end < $0.upperBound }) {
                    suffix = count - word.upperBound
                }
            }
            changed = prefix != previous.0 || suffix != previous.1
        }
        guard isWordSpan(prefix..<(before.count - suffix), words: oldWords),
              isWordSpan(prefix..<(after.count - suffix), words: newWords) else { return nil }
        let oldStart = original.index(original.startIndex, offsetBy: prefix)
        let oldEnd = original.index(original.endIndex, offsetBy: -suffix)
        let newStart = edited.index(edited.startIndex, offsetBy: prefix)
        let newEnd = edited.index(edited.endIndex, offsetBy: -suffix)
        guard !InputText.technicalRanges(in: original).contains(where: { $0.overlaps(oldStart..<oldEnd) }),
              !InputText.technicalRanges(in: edited).contains(where: { $0.overlaps(newStart..<newEnd) }) else { return nil }
        let oldWord = String(original[oldStart..<oldEnd])
        let newWord = String(edited[newStart..<newEnd])
        guard wordLike(oldWord), wordLike(newWord), MemoryText.normalized(oldWord) != MemoryText.normalized(newWord) else { return nil }
        return DictionaryCorrection(original: oldWord, replacement: newWord)
    }

    private static func wordOffsets(in text: String) -> [Range<Int>] {
        InputText.words(in: text).map {
            text.distance(from: text.startIndex, to: $0.lowerBound)..<text.distance(from: text.startIndex, to: $0.upperBound)
        }
    }

    private static func isWordSpan(_ range: Range<Int>, words: [Range<Int>]) -> Bool {
        guard !range.isEmpty else { return false }
        let contained = words.filter { $0.overlaps(range) }
        return (1...3).contains(contained.count)
            && contained.first?.lowerBound == range.lowerBound && contained.last?.upperBound == range.upperBound
    }

    private static func wordLike(_ text: String) -> Bool {
        (2...40).contains(text.count) && text.contains(where: \.isLetter)
            && text.allSatisfy { $0.isLetter || $0 == " " || $0 == "-" }
    }
}

struct DictionaryCorrectionTracker {
    let original: String
    private var lastText: String?
    private var changedAt: Date?

    init(original: String) { self.original = original }

    mutating func observe(_ text: String, at now: Date) -> DictionaryCorrection? {
        if text == original { lastText = nil; changedAt = nil; return nil }
        if lastText != text { lastText = text; changedAt = now; return nil }
        guard let changedAt, now.timeIntervalSince(changedAt) >= 2 else { return nil }
        return DictionaryCorrectionDetector.detect(original: original, edited: text)
    }
}
