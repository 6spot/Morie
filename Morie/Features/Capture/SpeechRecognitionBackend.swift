import Foundation
import Speech

enum SpeechRecognitionBackend: Sendable, Equatable {
    case speechTranscriber(Locale)
    case dictationTranscriber(Locale)

    var locale: Locale {
        switch self {
        case .speechTranscriber(let locale), .dictationTranscriber(let locale):
            locale
        }
    }

    var logName: String {
        switch self {
        case .speechTranscriber:
            "SpeechTranscriber"
        case .dictationTranscriber:
            "DictationTranscriber"
        }
    }

    var displayName: String { logName }

    var isFallback: Bool {
        if case .dictationTranscriber = self { return true }
        return false
    }

    var localeIdentifier: String {
        locale.identifier.replacingOccurrences(of: "_", with: "-")
    }

    static func preferred(for requestedLocale: Locale) async -> SpeechRecognitionBackend? {
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            return .speechTranscriber(locale)
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            return .dictationTranscriber(locale)
        }
        return nil
    }

    static func dictationFallback(for requestedLocale: Locale) async -> SpeechRecognitionBackend? {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            return nil
        }
        return .dictationTranscriber(locale)
    }
}
