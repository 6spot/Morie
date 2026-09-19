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

    func prepare(locale requestedLocale: Locale) async throws {
        guard activeSessionID == nil else { throw PipelineError.alreadyRunning }

        Diagnostics.record("Speech", "Preparing SpeechTranscriber for locale \(requestedLocale.identifier)")
        let transcriber = try await makeTranscriber(locale: requestedLocale)
        try Task.checkCancellation()

        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Diagnostics.record("Speech", "Speech asset installation required; starting download/install")
            try await installation.downloadAndInstall()
            Diagnostics.record("Speech", "Speech asset installation completed")
        } else {
            Diagnostics.record("Speech", "Speech assets already available")
        }

        try Task.checkCancellation()
        Diagnostics.record("Speech", "Speech preparation completed")
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

            let transcriber = try await makeTranscriber(locale: requestedLocale)
            try requireActiveSession(sessionID)
            Diagnostics.record("Speech", "SpeechTranscriber created for \(session)")

            let inputConverter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
            try requireActiveSession(sessionID)
            let source = try CaptureAudioSource(
                device: microphone,
                converter: inputConverter,
                destinationURL: sourceAudioURL,
                onAudioLevel: { level in onAudioLevel(sessionID, level) }
            )
            Diagnostics.record("Speech", "Single-output audio source created for \(session)")

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let analyzerInputs = source.analyzerInputs

            self.audioSource = source
            self.analyzer = analyzer

            if !dictionaryWords.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings = [.general: dictionaryWords]
                do { try await analyzer.setContext(context) }
                catch {
                    // Dictionary hints are optional; a rejected hint must not prevent intentional input.
                    Diagnostics.record("Speech", "Dictionary context was unavailable; continuing recognition", level: .warning)
                }
                try requireActiveSession(sessionID)
            }

            resultTask = Task {
                do {
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        guard activeSessionID == sessionID else { return }

                        let text = String(result.text.characters)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            hasTranscriptEvidence = true
                        }
                        if result.isFinal {
                            finalizedText = join(finalizedText, text)
                            volatileText = ""
                        } else {
                            volatileText = text
                        }

                        let combined = join(finalizedText, volatileText)
                        Diagnostics.record(
                            "SpeechText",
                            "Session \(session) transcriptCharacters=\(combined.count); final=\(result.isFinal)"
                        )
                        onTranscript(sessionID, combined)
                    }

                    Diagnostics.record("Speech", "Transcriber result stream ended for \(session)")
                } catch {
                    reportFailure(error, sessionID: sessionID, onFailure: onFailure)
                    throw error
                }
            }

            analysisTask = Task {
                do {
                    Diagnostics.record("Speech", "Analyzer sequence started for \(session)")
                    let lastSampleTime = try await analyzer.analyzeSequence(analyzerInputs)
                    Diagnostics.record("Speech", "Analyzer sequence ended for \(session)")
                    return lastSampleTime
                } catch {
                    reportFailure(error, sessionID: sessionID, onFailure: onFailure)
                    throw error
                }
            }

            try requireActiveSession(sessionID)
            source.start()
            Diagnostics.record("Speech", "Single-output AVCaptureSession started for \(session)")
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
            Diagnostics.record("Speech", "Normal stop completed for \(session); finalCharacters=\(result.transcript.count)")
            reset(sessionID: sessionID)
            return result
        } catch {
            Diagnostics.record("Speech", "Normal stop failed for \(session): \(error.localizedDescription)", level: .error)
            if let result = await stopImmediately(sessionID: sessionID) {
                throw PipelineError.recognitionFailed(error.localizedDescription, result)
            }
            // An external interruption already took ownership of the snapshot.
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

        // Detach ownership before awaiting native teardown. A concurrent finish
        // cannot cancel the analyzer twice or overwrite the next session.
        reset(sessionID: sessionID)

        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        _ = await analysisTask?.result
        _ = await resultTask?.result

        Diagnostics.record("Speech", "Pipeline stopped; source audio kept for \(session)", level: .warning)
        return result
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

    private func makeTranscriber(locale requestedLocale: Locale) async throws -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            Diagnostics.record("Speech", "Unsupported requested locale: \(requestedLocale.identifier)", level: .error)
            throw PipelineError.unsupportedLocale
        }

        Diagnostics.record("Speech", "Resolved Speech locale: \(locale.identifier)")
        return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
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
