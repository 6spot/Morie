import Foundation
import NaturalLanguage

struct MemoryContextMatch: Equatable, Identifiable, Sendable {
    let memory: MemorySnapshot
    let matchedTerm: String
    var id: UUID { memory.id }
}

enum MemoryContextRetriever {
    static func retrieve(for text: String, from memories: [MemorySnapshot], limit: Int = 8) -> [MemoryContextMatch] {
        let query = MemoryText.normalized(text)
        let words = wordRanges(in: query)
        guard !words.isEmpty, limit > 0 else { return [] }

        let matches: [(MemoryContextMatch, Int)] = memories.compactMap { memory in
            guard memory.status == .active, memory.userConfirmed else { return nil }
            var bestMatch: (MemoryContextMatch, Int)?
            for (index, term) in ([memory.name] + memory.aliases).enumerated() {
                let phrase = MemoryText.normalized(term)
                let wordCount = wordRanges(in: phrase).count
                guard wordCount > 0 else { continue }
                var start = query.startIndex
                while start < query.endIndex,
                      let range = query.range(of: phrase, range: start..<query.endIndex) {
                    let splitsWord = words.contains { word in
                        (word.lowerBound < range.lowerBound && range.lowerBound < word.upperBound)
                            || (word.lowerBound < range.upperBound && range.upperBound < word.upperBound)
                    }
                    if !splitsWord {
                        // Stored names/aliases are limited to 120 characters.
                        let score = (index == 0 ? 1_000 : 0) + wordCount
                        if score > (bestMatch?.1 ?? 0) {
                            bestMatch = (MemoryContextMatch(memory: memory, matchedTerm: term), score)
                        }
                        break
                    }
                    start = range.upperBound
                }
            }
            return bestMatch
        }

        return matches.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.memory.updatedAt != rhs.0.memory.updatedAt { return lhs.0.memory.updatedAt > rhs.0.memory.updatedAt }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }.prefix(min(limit, 8)).map(\.0)
    }

    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            words.append(range)
            return true
        }
        return words
    }
}
