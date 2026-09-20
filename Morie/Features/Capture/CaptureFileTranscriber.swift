import AVFoundation
import Foundation
import Speech

enum CaptureFileTranscriber {
    enum TranscriptionError: LocalizedError {
        case unsupportedLocale
        case emptyRecognition

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "Apple 语音识别暂不支持这段录音的语言。"
            case .emptyRecognition: "未识别到语音，已保存的文字和录音均已保留。"
            }
        }
    }

    static func recognize(_ url: URL, locale requestedLocale: Locale) async throws -> String {
        try await recognize(url, locale: requestedLocale, dictionaryWords: [])
    }

    static func recognize(
        _ url: URL,
        locale requestedLocale: Locale,
        dictionaryWords: [String],
        applicationContextWords: [String] = []
    ) async throws -> String {
        try Task.checkCancellation()
        let probe = try AVAudioFile(forReading: url)
        guard probe.length > 0 else { throw TranscriptionError.emptyRecognition }

        guard let backend = await SpeechRecognitionBackend.preferred(for: requestedLocale) else {
            throw TranscriptionError.unsupportedLocale
        }

        let contextualWords = SpeechContextHints.merged(
            dictionaryWords: dictionaryWords,
            applicationContextWords: applicationContextWords
        )
        Diagnostics.record(
            "Speech",
            "Saved-audio recognition selected \(backend.logName) for \(backend.locale.identifier); dictionaryHints=\(dictionaryWords.count); applicationHints=\(applicationContextWords.count); contextualHints=\(contextualWords.count)"
        )

        switch backend {
        case .speechTranscriber(let locale):
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            do {
                try await installAssetsIfNeeded(for: transcriber)
            } catch {
                if let fallback = await SpeechRecognitionBackend.dictationFallback(for: requestedLocale),
                   case .dictationTranscriber(let fallbackLocale) = fallback {
                    Diagnostics.record(
                        "Speech",
                        "SpeechTranscriber asset preparation failed for saved audio; falling back to DictationTranscriber: \(error.localizedDescription)",
                        level: .warning
                    )
                    return try await recognizeWithDictation(
                        url,
                        locale: fallbackLocale,
                        contextualWords: contextualWords,
                        dictionaryHintCount: dictionaryWords.count,
                        applicationHintCount: applicationContextWords.count
                    )
                }
                throw error
            }
            return try await recognizeWithSpeech(
                url,
                transcriber: transcriber,
                contextualWords: contextualWords,
                dictionaryHintCount: dictionaryWords.count,
                applicationHintCount: applicationContextWords.count
            )

        case .dictationTranscriber(let locale):
            return try await recognizeWithDictation(
                url,
                locale: locale,
                contextualWords: contextualWords,
                dictionaryHintCount: dictionaryWords.count,
                applicationHintCount: applicationContextWords.count
            )
        }
    }

    private static func recognizeWithSpeech(
        _ url: URL,
        transcriber: SpeechTranscriber,
        contextualWords: [String],
        dictionaryHintCount: Int,
        applicationHintCount: Int
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: url)
        let detector = SpeechDetector()
        let modules: [any SpeechModule] = [detector, transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        await applyRecognitionContext(
            contextualWords,
            dictionaryHintCount: dictionaryHintCount,
            applicationHintCount: applicationHintCount,
            analyzer: analyzer
        )

        return try await withTaskCancellationHandler {
            let results = Task {
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard result.isFinal else { continue }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { segments.append(text) }
                }
                return segments.joined()
            }
            defer { results.cancel() }

            do {
                try Task.checkCancellation()
                let lastSample = try await analyzer.analyzeSequence(from: audioFile)
                try Task.checkCancellation()
                if let lastSample {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let text = try await results.value
                try Task.checkCancellation()
                guard !text.isEmpty else { throw TranscriptionError.emptyRecognition }
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                if SpeechRecognitionFailureClassifier.isRejection(error) {
                    Diagnostics.record(
                        "SpeechQuality",
                        "Saved-audio recognizer rejected the recording; treating it as empty recognition"
                    )
                    throw TranscriptionError.emptyRecognition
                }
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private static func recognizeWithDictation(
        _ url: URL,
        locale: Locale,
        contextualWords: [String],
        dictionaryHintCount: Int,
        applicationHintCount: Int
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: url)
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        let detector = SpeechDetector()
        let modules: [any SpeechModule] = [detector, transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        await applyRecognitionContext(
            contextualWords,
            dictionaryHintCount: dictionaryHintCount,
            applicationHintCount: applicationHintCount,
            analyzer: analyzer
        )

        return try await withTaskCancellationHandler {
            let results = Task {
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard result.isFinal else { continue }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { segments.append(text) }
                }
                return segments.joined()
            }
            defer { results.cancel() }

            do {
                try Task.checkCancellation()
                let lastSample = try await analyzer.analyzeSequence(from: audioFile)
                try Task.checkCancellation()
                if let lastSample {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let text = try await results.value
                try Task.checkCancellation()
                guard !text.isEmpty else { throw TranscriptionError.emptyRecognition }
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                if SpeechRecognitionFailureClassifier.isRejection(error) {
                    Diagnostics.record(
                        "SpeechQuality",
                        "Saved-audio recognizer rejected the recording; treating it as empty recognition"
                    )
                    throw TranscriptionError.emptyRecognition
                }
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    static func preferredTranscript(live: String, accurate: String?) -> String {
        guard let accurate,
              !accurate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return live
        }
        return accurate
    }

    private static func applyRecognitionContext(
        _ contextualWords: [String],
        dictionaryHintCount: Int,
        applicationHintCount: Int,
        analyzer: SpeechAnalyzer
    ) async {
        guard !contextualWords.isEmpty else { return }

        let context = AnalysisContext()
        context.contextualStrings = [.general: contextualWords]
        do {
            try await analyzer.setContext(context)
            Diagnostics.record(
                "SpeechQuality",
                "Applied \(contextualWords.count) contextual strings to saved-audio recognition; dictionaryHints=\(dictionaryHintCount); applicationHints=\(applicationHintCount)"
            )
        } catch {
            Diagnostics.record(
                "Speech",
                "Saved-audio recognition context was unavailable; continuing recognition: \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        let detector = SpeechDetector()
        let modules: [any SpeechModule] = [detector, transcriber]
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await installation.downloadAndInstall()
        }
    }
}


enum SpeechRecognitionFailureClassifier {
    static func isRejection(_ error: Error) -> Bool {
        var pending = [error as NSError]
        var visited = Set<ObjectIdentifier>()

        while let current = pending.popLast() {
            let identity = ObjectIdentifier(current)
            guard visited.insert(identity).inserted else { continue }

            let descriptions = [
                current.localizedDescription,
                current.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
                current.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String,
            ].compactMap { $0 }

            if descriptions.contains(where: isRecognitionRejectionText) {
                return true
            }

            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
        }

        return false
    }

    static func diagnosticDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }

    private static func isRecognitionRejectionText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("reject")
            && (normalized.contains("recog") || normalized.contains("recognition"))
    }
}
