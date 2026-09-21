import Foundation

enum SpeechContextHints {
    static let maximumCount = 48
    static let reservedApplicationCount = 16

    static func merged(
        dictionaryWords: [String],
        applicationContextWords: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ words: ArraySlice<String>, limit: Int) {
            guard limit > 0 else { return }
            var added = 0
            for raw in words {
                guard result.count < maximumCount, added < limit else { break }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.count <= 80 else { continue }
                let key = value.folding(
                    options: [.caseInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                guard seen.insert(key).inserted else { continue }
                result.append(value)
                added += 1
            }
        }

        let applicationBudget = applicationContextWords.isEmpty
            ? 0
            : min(reservedApplicationCount, maximumCount)
        let dictionaryBudget = maximumCount - applicationBudget

        append(dictionaryWords[...], limit: dictionaryBudget)
        append(applicationContextWords[...], limit: applicationBudget)

        if result.count < maximumCount {
            append(dictionaryWords.dropFirst(dictionaryBudget), limit: maximumCount - result.count)
        }
        if result.count < maximumCount {
            append(applicationContextWords.dropFirst(applicationBudget), limit: maximumCount - result.count)
        }

        return result
    }
}
