import AVFoundation
import CoreMedia
import Foundation
import Speech

actor SpeechPipeline {
    enum PipelineError: LocalizedError {
        case alreadyRunning
        case noMicrophone
        case unsupportedLocale
        case notRunning
        case recognitionFailed(String, Result)

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "录音正在进行中。"
            case .noMicrophone: "没有可用的麦克风。"
            case .unsupportedLocale: "Apple 语音转写暂不支持当前输入语言。"
            case .notRunning: "当前没有正在进行的录音。"
            case .recognitionFailed(let reason, _): reason
            }
        }
    }

    struct Result: Sendable {
        let transcript: String
        let sourceAudio: CapturedSourceAudio
    }

    private struct LiveBackendSetup {
        let analyzer: SpeechAnalyzer
        let source: CaptureAudioSource
        let resultTask: Task<Void, Error>
    }

    private var activeSessionID: UUID?
    private var analyzer: SpeechAnalyzer?
    private var audioSource: CaptureAudioSource?
    private var finalizedSourceAudio: CapturedSourceAudio?
    private var resultTask: Task<Void, Error>?
    private var analysisTask: Task<CMTime?, Error>?
    private var finalizedText = ""
    private var volatileText = ""
    private var hasTranscriptEvidence = false
    private var isFinalizing = false
    private var reportedFailure = false
    private var preparedBackend: SpeechRecognitionBackend?

    func prepare(locale requestedLocale: Locale) async throws {
        guard activeSessionID == nil else { throw PipelineError.alreadyRunning }

        guard let preferred = await SpeechRecognitionBackend.preferred(for: requestedLocale) else {
            Diagnostics.record("Speech", "Unsupported requested locale: \(requestedLocale.identifier)", level: .error)
            throw PipelineError.unsupportedLocale
        }

        Diagnostics.record(
            "Speech",
            "Preparing \(preferred.logName) for locale \(preferred.locale.identifier)"
        )

        do {
            try await prepareAssets(for: preferred)
            try Task.checkCancellation()
            preparedBackend = preferred
            Diagnostics.record("Speech", "\(preferred.logName) preparation completed")
        } catch {
            guard case .speechTranscriber = preferred,
                  let fallback = await SpeechRecognitionBackend.dictationFallback(for: requestedLocale) else {
                throw error
            }

            Diagnostics.record(
                "Speech",
                "SpeechTranscriber preparation failed; falling back to DictationTranscriber: \(error.localizedDescription)",
                level: .warning
            )
            try await prepareAssets(for: fallback)
            try Task.checkCancellation()
            preparedBackend = fallback
            Diagnostics.record("Speech", "DictationTranscriber fallback preparation completed")
        }
    }

    func start(
        sessionID: UUID,
        locale requestedLocale: Locale,
        sourceAudioURL: URL,
        dictionaryWords: [String] = [],
        onTranscript: @escaping @Sendable (UUID, String) -> Void,
        onAudioLevel: @escaping @Sendable (UUID, Double) -> Void,
        onFailure: @escaping @Sendable (UUID, String) -> Void
    ) async throws {
        guard activeSessionID == nil else { throw PipelineError.alreadyRunning }
        activeSessionID = sessionID
        finalizedText = ""
        volatileText = ""
        hasTranscriptEvidence = false

        let session = label(sessionID)
        Diagnostics.record("Speech", "Pipeline start requested for \(session)")

        do {
            try requireActiveSession(sessionID)

            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                Diagnostics.record("Speech", "No default microphone available for \(session)", level: .error)
                throw PipelineError.noMicrophone
            }
            Diagnostics.record("Speech", "Default microphone resolved for \(session): \(microphone.localizedName)")

            let backend: SpeechRecognitionBackend
            if let preparedBackend {
                backend = preparedBackend
            } else if let resolved = await SpeechRecognitionBackend.preferred(for: requestedLocale) {
                try await prepareAssets(for: resolved)
                backend = resolved
                preparedBackend = resolved
            } else {
                throw PipelineError.unsupportedLocale
            }

            try requireActiveSession(sessionID)
            Diagnostics.record(
                "SpeechQuality",
                "Session \(session) backend=\(backend.logName); locale=\(backend.locale.identifier); dictionaryHints=\(dictionaryWords.count)"
            )

            let setup = try await configureLiveBackend(
                backend,
                sessionID: sessionID,
                sessionLabel: session,
                microphone: microphone,
                sourceAudioURL: sourceAudioURL,
                dictionaryWords: dictionaryWords,
                onTranscript: onTranscript,
                onAudioLevel: onAudioLevel,
                onFailure: onFailure
            )
            try requireActiveSession(sessionID)

            audioSource = setup.source
            analyzer = setup.analyzer
            resultTask = setup.resultTask

            let analyzerInputs = setup.source.analyzerInputs
            analysisTask = Task {
                do {
                    Diagnostics.record("Speech", "Analyzer sequence started for \(session)")
                    let lastSampleTime = try await setup.analyzer.analyzeSequence(analyzerInputs)
                    Diagnostics.record("Speech", "Analyzer sequence ended for \(session)")
                    return lastSampleTime
                } catch {
                    reportFailure(error, sessionID: sessionID, onFailure: onFailure)
                    throw error
                }
            }

            try requireActiveSession(sessionID)
            setup.source.start()
            Diagnostics.record(
                "Speech",
                "Single-output AVCaptureSession started for \(session) using \(backend.logName)"
            )
            try requireActiveSession(sessionID)
        } catch {
            Diagnostics.record("Speech", "Pipeline start failed for \(session): \(error.localizedDescription)", level: .error)
            if let result = await stopImmediately(sessionID: sessionID) {
                throw PipelineError.recognitionFailed(error.localizedDescription, result)
            }
            throw error
        }
    }

    func stop(sessionID: UUID) async throws -> Result {
        try requireActiveSession(sessionID)
        guard let analyzer, let analysisTask else {
            throw PipelineError.notRunning
        }

        let session = label(sessionID)
        Diagnostics.record("Speech", "Normal stop started for \(session)")

        isFinalizing = true
        guard let completion = audioSource?.finish() else { throw PipelineError.notRunning }
        finalizedSourceAudio = completion.sourceAudio
        self.audioSource = nil
        Diagnostics.record("Speech", "Capture session stopped and source audio finalized for \(session)")

        do {
            if let error = completion.error { throw error }
            let lastSampleTime = try await analysisTask.value
            try requireActiveSession(sessionID)

            if let lastSampleTime {
                Diagnostics.record("Speech", "Finalizing analyzer through last sample for \(session)")
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                Diagnostics.record("Speech", "Analyzer returned no last sample; cancelling immediately for \(session)", level: .warning)
                await analyzer.cancelAndFinishNow()
            }

            if let resultTask {
                try await resultTask.value
            }

            try requireActiveSession(sessionID)

            let result = snapshot(sourceAudio: completion.sourceAudio)
            Diagnostics.record(
                "SpeechQuality",
                "Session \(session) finalCharacters=\(result.transcript.count); backend=\(preparedBackend?.logName ?? "unknown")"
            )
            Diagnostics.record("Speech", "Normal stop completed for \(session); finalCharacters=\(result.transcript.count)")
            reset(sessionID: sessionID)
            return result
        } catch {
            Diagnostics.record("Speech", "Normal stop failed for \(session): \(error.localizedDescription)", level: .error)
            if let result = await stopImmediately(sessionID: sessionID) {
                throw PipelineError.recognitionFailed(error.localizedDescription, result)
            }
            throw CancellationError()
        }
    }

    func stopImmediately(sessionID: UUID) async -> Result? {
        guard activeSessionID == sessionID else { return nil }

        let session = label(sessionID)
        Diagnostics.record("Speech", "Stopping pipeline immediately for \(session)", level: .warning)

        let sourceAudio = audioSource?.stopImmediately() ?? finalizedSourceAudio
        let result = sourceAudio.map { snapshot(sourceAudio: $0) }
        let analyzer = analyzer
        let analysisTask = analysisTask
        let resultTask = resultTask

        reset(sessionID: sessionID)

        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        _ = await analysisTask?.result
        _ = await resultTask?.result

        Diagnostics.record("Speech", "Pipeline stopped; source audio kept for \(session)", level: .warning)
        return result
    }

    private func configureLiveBackend(
        _ backend: SpeechRecognitionBackend,
        sessionID: UUID,
        sessionLabel: String,
        microphone: AVCaptureDevice,
        sourceAudioURL: URL,
        dictionaryWords: [String],
        onTranscript: @escaping @Sendable (UUID, String) -> Void,
        onAudioLevel: @escaping @Sendable (UUID, Double) -> Void,
        onFailure: @escaping @Sendable (UUID, String) -> Void
    ) async throws -> LiveBackendSetup {
        switch backend {
        case .speechTranscriber(let locale):
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
            try requireActiveSession(sessionID)

            let source = try CaptureAudioSource(
                device: microphone,
                converter: converter,
                destinationURL: sourceAudioURL,
                onAudioLevel: { level in onAudioLevel(sessionID, level) }
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await applyDictionaryContext(dictionaryWords, analyzer: analyzer, sessionID: sessionID)

            let task = Task {
                do {
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        guard activeSessionID == sessionID else { return }
                        consume(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            sessionID: sessionID,
                            sessionLabel: sessionLabel,
                            onTranscript: onTranscript
                        )
                    }
                    Diagnostics.record("Speech", "SpeechTranscriber result stream ended for \(sessionLabel)")
                } catch {
                    reportFailure(error, sessionID: sessionID, onFailure: onFailure)
                    throw error
                }
            }

            Diagnostics.record("Speech", "SpeechTranscriber configured for \(sessionLabel)")
            return LiveBackendSetup(analyzer: analyzer, source: source, resultTask: task)

        case .dictationTranscriber(let locale):
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
            try requireActiveSession(sessionID)

            let source = try CaptureAudioSource(
                device: microphone,
                converter: converter,
                destinationURL: sourceAudioURL,
                onAudioLevel: { level in onAudioLevel(sessionID, level) }
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await applyDictionaryContext(dictionaryWords, analyzer: analyzer, sessionID: sessionID)

            let task = Task {
                do {
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        guard activeSessionID == sessionID else { return }
                        consume(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            sessionID: sessionID,
                            sessionLabel: sessionLabel,
                            onTranscript: onTranscript
                        )
                    }
                    Diagnostics.record("Speech", "DictationTranscriber result stream ended for \(sessionLabel)")
                } catch {
                    reportFailure(error, sessionID: sessionID, onFailure: onFailure)
                    throw error
                }
            }

            Diagnostics.record("Speech", "DictationTranscriber configured for \(sessionLabel)")
            return LiveBackendSetup(analyzer: analyzer, source: source, resultTask: task)
        }
    }

    private func consume(
        text: String,
        isFinal: Bool,
        sessionID: UUID,
        sessionLabel: String,
        onTranscript: @escaping @Sendable (UUID, String) -> Void
    ) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasTranscriptEvidence = true
        }

        if isFinal {
            finalizedText = join(finalizedText, text)
            volatileText = ""
        } else {
            volatileText = text
        }

        let combined = join(finalizedText, volatileText)
        Diagnostics.record(
            "SpeechText",
            "Session \(sessionLabel) transcriptCharacters=\(combined.count); final=\(isFinal)"
        )
        onTranscript(sessionID, combined)
    }

    private func applyDictionaryContext(
        _ dictionaryWords: [String],
        analyzer: SpeechAnalyzer,
        sessionID: UUID
    ) async throws {
        guard !dictionaryWords.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings = [.general: dictionaryWords]
        do {
            try await analyzer.setContext(context)
            Diagnostics.record(
                "SpeechQuality",
                "Applied \(dictionaryWords.count) contextual dictionary strings for \(label(sessionID))"
            )
        } catch {
            Diagnostics.record(
                "Speech",
                "Dictionary context was unavailable; continuing recognition: \(error.localizedDescription)",
                level: .warning
            )
        }
        try requireActiveSession(sessionID)
    }

    private func prepareAssets(for backend: SpeechRecognitionBackend) async throws {
        switch backend {
        case .speechTranscriber(let locale):
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Diagnostics.record("Speech", "SpeechTranscriber asset installation required")
                try await installation.downloadAndInstall()
                Diagnostics.record("Speech", "SpeechTranscriber asset installation completed")
            } else {
                Diagnostics.record("Speech", "SpeechTranscriber assets already available")
            }

        case .dictationTranscriber(let locale):
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Diagnostics.record("Speech", "DictationTranscriber asset installation required")
                try await installation.downloadAndInstall()
                Diagnostics.record("Speech", "DictationTranscriber asset installation completed")
            } else {
                Diagnostics.record("Speech", "DictationTranscriber assets already available")
            }
        }
    }

    private func snapshot(sourceAudio: CapturedSourceAudio) -> Result {
        Result(
            transcript: join(finalizedText, volatileText),
            sourceAudio: CapturedSourceAudio(
                url: sourceAudio.url,
                duration: sourceAudio.duration,
                hasMeaningfulAudio: hasTranscriptEvidence ? true : sourceAudio.hasMeaningfulAudio
            )
        )
    }

    private func reportFailure(
        _ error: Error,
        sessionID: UUID,
        onFailure: @Sendable (UUID, String) -> Void
    ) {
        guard activeSessionID == sessionID, !isFinalizing, !reportedFailure, !Task.isCancelled else { return }
        reportedFailure = true
        onFailure(sessionID, error.localizedDescription)
    }

    private func requireActiveSession(_ sessionID: UUID) throws {
        try Task.checkCancellation()
        guard activeSessionID == sessionID else {
            throw CancellationError()
        }
    }

    private func reset(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }

        analysisTask?.cancel()
        resultTask?.cancel()
        analysisTask = nil
        resultTask = nil
        audioSource = nil
        finalizedSourceAudio = nil
        analyzer = nil
        activeSessionID = nil
        finalizedText = ""
        volatileText = ""
        hasTranscriptEvidence = false
        isFinalizing = false
        reportedFailure = false
    }

    private func join(_ lhs: String, _ rhs: String) -> String {
        SpeechTranscriptAssembler.join(lhs, rhs)
    }

    private func label(_ sessionID: UUID) -> String {
        String(sessionID.uuidString.prefix(8))
    }
}
