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
        let queryWordRanges = InputText.words(in: text)
        let active = memories.filter { $0.status == .active }
        let indexed = active.map { memory in
            (memory, Set(terms(memory.name + " " + memory.notes)))
        }

        var frequency: [String: Int] = [:]
        for (_, memoryTerms) in indexed {
            for term in memoryTerms { frequency[term, default: 0] += 1 }
        }

        let matches: [(MemoryContextMatch, Int)] = indexed.compactMap { memory, memoryTerms in
            // Naming the Memory topic explicitly is the strongest relevance signal.
            if !InputText.literalRanges(of: memory.name, in: text, wordRanges: queryWordRanges).isEmpty {
                return (MemoryContextMatch(memory: memory, matchedTerm: memory.name), 100 + memory.name.count)
            }

            let shared = memoryTerms.intersection(queryTerms)
            guard !shared.isEmpty else { return nil }

            // A single weak/common word is not enough to inject personal facts into
            // cleanup. Specific long terms, unique terms, or several shared terms
            // remain useful without requiring the Memory title to be spoken.
            let relevance = shared.reduce(0) { score, term in
                score + min(term.count, 8) + (frequency[term] == 1 ? 4 : 0)
            }
            guard shared.count >= 2 || relevance >= 5 else { return nil }

            return (
                MemoryContextMatch(memory: memory, matchedTerm: shared.sorted().joined(separator: ", ")),
                relevance
            )
        }

        return matches.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.memory.updatedAt != $1.0.memory.updatedAt { return $0.0.memory.updatedAt > $1.0.memory.updatedAt }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }.prefix(min(limit, 8)).map(\.0)
    }

    private static func terms(_ text: String) -> [String] {
        let normalized = MemoryText.normalized(text)
        let stopwords: Set<String> = [
            "this", "that", "with", "have", "from", "about", "your", "mine", "the", "and", "are", "was", "for",
            "you", "my", "our", "project", "work", "working", "issue", "problem", "feature", "system", "input",
            "use", "using", "today", "thing", "things",
            "我们", "我的", "这个", "那个", "现在", "已经", "需要", "可以", "就是", "自己", "一个", "今天",
            "项目", "工作", "问题", "功能", "系统", "输入", "使用", "处理", "开发", "内容", "情况", "东西", "时候",
        ]
        return InputText.words(in: normalized).map { String(normalized[$0]) }.filter {
            $0.count > 1 && !stopwords.contains($0) && $0.contains(where: \.isLetter)
        }
    }
}
