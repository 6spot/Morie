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
        applicationContextWords: [String] = [],
        captureID: UUID? = nil
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
        DevelopmentDiagnostics.record(
            "AccurateSpeech",
            captureID: captureID,
            "start; backend=\(backend.logName); locale=\(backend.locale.identifier); file=\(url.lastPathComponent); frames=\(probe.length); sampleRate=\(probe.processingFormat.sampleRate)"
        )
        DevelopmentDiagnostics.list(
            "AccurateSpeech",
            captureID: captureID,
            label: "contextualHints",
            contextualWords
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
                        applicationHintCount: applicationContextWords.count,
                        captureID: captureID
                    )
                }
                throw error
            }
            return try await recognizeWithSpeech(
                url,
                transcriber: transcriber,
                contextualWords: contextualWords,
                dictionaryHintCount: dictionaryWords.count,
                applicationHintCount: applicationContextWords.count,
                captureID: captureID
            )

        case .dictationTranscriber(let locale):
            return try await recognizeWithDictation(
                url,
                locale: locale,
                contextualWords: contextualWords,
                dictionaryHintCount: dictionaryWords.count,
                applicationHintCount: applicationContextWords.count,
                captureID: captureID
            )
        }
    }

    private static func recognizeWithSpeech(
        _ url: URL,
        transcriber: SpeechTranscriber,
        contextualWords: [String],
        dictionaryHintCount: Int,
        applicationHintCount: Int,
        captureID: UUID?
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: url)
        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        await applyRecognitionContext(
            contextualWords,
            dictionaryHintCount: dictionaryHintCount,
            applicationHintCount: applicationHintCount,
            analyzer: analyzer,
            captureID: captureID
        )

        return try await withTaskCancellationHandler {
            let results = Task {
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard result.isFinal else { continue }
                    let text = String(result.text.characters)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(text)
                    }
                }
                return segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
                DevelopmentDiagnostics.text(
                    "AccurateSpeech",
                    captureID: captureID,
                    label: "speechTranscriberFinal",
                    text,
                    limit: 8_000
                )
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                if SpeechRecognitionFailureClassifier.isRejection(error) {
                    DevelopmentDiagnostics.record(
                        "AccurateSpeech",
                        captureID: captureID,
                        level: .warning,
                        "recognitionRejected; errorType=\(DevelopmentDiagnostics.errorType(error))"
                    )
                    Diagnostics.record(
                        "SpeechQuality",
                        "Saved-audio recognizer rejected the recording; treating it as empty recognition"
                    )
                    throw TranscriptionError.emptyRecognition
                }
                DevelopmentDiagnostics.record(
                    "AccurateSpeech",
                    captureID: captureID,
                    level: .error,
                    "recognitionFailed; errorType=\(DevelopmentDiagnostics.errorType(error))"
                )
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
        applicationHintCount: Int,
        captureID: UUID?
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: url)
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        await applyRecognitionContext(
            contextualWords,
            dictionaryHintCount: dictionaryHintCount,
            applicationHintCount: applicationHintCount,
            analyzer: analyzer,
            captureID: captureID
        )

        return try await withTaskCancellationHandler {
            let results = Task {
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard result.isFinal else { continue }
                    let text = String(result.text.characters)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(text)
                    }
                }
                return segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
                DevelopmentDiagnostics.text(
                    "AccurateSpeech",
                    captureID: captureID,
                    label: "dictationTranscriberFinal",
                    text,
                    limit: 8_000
                )
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                if SpeechRecognitionFailureClassifier.isRejection(error) {
                    DevelopmentDiagnostics.record(
                        "AccurateSpeech",
                        captureID: captureID,
                        level: .warning,
                        "recognitionRejected; errorType=\(DevelopmentDiagnostics.errorType(error))"
                    )
                    Diagnostics.record(
                        "SpeechQuality",
                        "Saved-audio recognizer rejected the recording; treating it as empty recognition"
                    )
                    throw TranscriptionError.emptyRecognition
                }
                DevelopmentDiagnostics.record(
                    "AccurateSpeech",
                    captureID: captureID,
                    level: .error,
                    "recognitionFailed; errorType=\(DevelopmentDiagnostics.errorType(error))"
                )
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    static func preferredTranscript(live: String, accurate: String?) -> String {
        guard let accurate else { return live }

        let liveText = live.trimmingCharacters(in: .whitespacesAndNewlines)
        let accurateText = accurate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accurateText.isEmpty else { return live }
        guard !liveText.isEmpty else { return accurateText }

        let liveCount = comparableCharacterCount(liveText)
        let accurateCount = comparableCharacterCount(accurateText)

        // Saved-audio recognition normally differs in wording or punctuation, not
        // by losing most of the utterance or inventing a much larger transcript.
        // Reject only gross regressions so genuine accuracy improvements still win.
        if liveCount >= 12 {
            if accurateCount * 100 < liveCount * 55 {
                return live
            }
            if accurateCount > liveCount * 2 + 24 {
                return live
            }
        }

        return accurateText
    }

    private static func comparableCharacterCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.alphanumerics.contains(scalar)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value) {
                count += 1
            }
        }
    }

    private static func applyRecognitionContext(
        _ contextualWords: [String],
        dictionaryHintCount: Int,
        applicationHintCount: Int,
        analyzer: SpeechAnalyzer,
        captureID: UUID?
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
            DevelopmentDiagnostics.record(
                "AccurateSpeech",
                captureID: captureID,
                "contextApplied; total=\(contextualWords.count); dictionary=\(dictionaryHintCount); application=\(applicationHintCount)"
            )
        } catch {
            Diagnostics.record(
                "Speech",
                "Saved-audio recognition context was unavailable; continuing recognition: \(error.localizedDescription)",
                level: .warning
            )
            DevelopmentDiagnostics.record(
                "AccurateSpeech",
                captureID: captureID,
                level: .warning,
                "contextApplyFailed; errorType=\(DevelopmentDiagnostics.errorType(error))"
            )
        }
    }

    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        let modules: [any SpeechModule] = [transcriber]
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
