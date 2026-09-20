import Foundation

enum SpeechContextHints {
    static let maximumCount = 48

    static func merged(
        dictionaryWords: [String],
        applicationContextWords: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in dictionaryWords + applicationContextWords {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 80 else { continue }
            let key = value.folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(key).inserted else { continue }
            result.append(value)
            if result.count == maximumCount { break }
        }
        return result
    }
}
