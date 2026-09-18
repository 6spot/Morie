import Foundation

struct MemoryContextMatch: Codable, Equatable, Identifiable, Sendable {
    let memory: MemorySnapshot
    let matchedTerm: String
    var id: UUID { memory.id }
}

enum MemoryContextRetriever {
    static func retrieve(for text: String, from memories: [MemorySnapshot], limit: Int = 8) -> [MemoryContextMatch] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, limit > 0 else { return [] }
        let queryTerms = Set(terms(text))
        let matches: [(MemoryContextMatch, Int)] = memories.compactMap { memory in
            guard memory.status == .active else { return nil }
            if !InputText.literalRanges(of: memory.name, in: text).isEmpty {
                return (MemoryContextMatch(memory: memory, matchedTerm: memory.name), 100 + memory.name.count)
            }
            let shared = Set(terms(memory.name + " " + memory.notes)).intersection(queryTerms)
            guard !shared.isEmpty else { return nil }
            return (MemoryContextMatch(memory: memory, matchedTerm: shared.sorted().joined(separator: ", ")), shared.count)
        }
        return matches.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.memory.updatedAt != $1.0.memory.updatedAt { return $0.0.memory.updatedAt > $1.0.memory.updatedAt }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }.prefix(min(limit, 8)).map(\.0)
    }

    private static func terms(_ text: String) -> [String] {
        let normalized = MemoryText.normalized(text)
        let stopwords: Set<String> = ["this", "that", "with", "have", "from", "about", "your", "mine", "the", "and", "are", "was", "for", "you", "my", "our", "我们", "我的", "这个", "那个", "现在", "已经", "需要", "可以", "就是", "自己", "一个"]
        return InputText.words(in: normalized).map { String(normalized[$0]) }.filter {
            $0.count > 1 && !stopwords.contains($0) && $0.contains(where: \.isLetter)
        }
    }
}
