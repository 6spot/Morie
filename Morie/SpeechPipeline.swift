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

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "Speech capture is already running."
            case .noMicrophone: "No audio capture device is available."
            case .unsupportedLocale: "The current locale is not supported by SpeechTranscriber."
            case .notRunning: "Speech capture is not running."
            }
        }
    }

    private var activeSessionID: UUID?
    private var analyzer: SpeechAnalyzer?
    private var provider: CaptureInputSequenceProvider?
    private var resultTask: Task<Void, Error>?
    private var analysisTask: Task<CMTime?, Error>?
    private var finalizedText = ""
    private var volatileText = ""

    /// Prepare the current locale before the hotkey becomes Ready. Asset
    /// installation can take much longer than a push-to-talk press, so it must
    /// not be deferred until the user is already holding the shortcut.
    func prepare(locale requestedLocale: Locale) async throws {
        guard activeSessionID == nil else { throw PipelineError.alreadyRunning }

        let transcriber = try await makeTranscriber(locale: requestedLocale)
        try Task.checkCancellation()

        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }

        try Task.checkCancellation()
    }

    func start(
        sessionID: UUID,
        locale requestedLocale: Locale,
        onTranscript: @escaping @Sendable (UUID, String) -> Void
    ) async throws {
        guard activeSessionID == nil else { throw PipelineError.alreadyRunning }
        activeSessionID = sessionID
        finalizedText = ""
        volatileText = ""

        var preparedProvider: CaptureInputSequenceProvider?
        var preparedAnalyzer: SpeechAnalyzer?

        do {
            try requireActiveSession(sessionID)

            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                throw PipelineError.noMicrophone
            }

            let transcriber = try await makeTranscriber(locale: requestedLocale)
            try requireActiveSession(sessionID)

            let provider = try await CaptureInputSequenceProvider.providerWithSession(
                from: microphone,
                compatibleWith: [transcriber],
                priority: .userInitiated
            )
            preparedProvider = provider
            try requireActiveSession(sessionID)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            preparedAnalyzer = analyzer
            let analyzerInputs = provider.analyzerInputs

            self.provider = provider
            self.analyzer = analyzer

            resultTask = Task {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard activeSessionID == sessionID else { return }

                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalizedText = join(finalizedText, text)
                        volatileText = ""
                    } else {
                        volatileText = text
                    }

                    onTranscript(sessionID, join(finalizedText, volatileText))
                }
            }

            analysisTask = Task {
                try await analyzer.analyzeSequence(analyzerInputs)
            }

            provider.captureSession.startRunning()
            try requireActiveSession(sessionID)
        } catch {
            preparedProvider?.captureSession.stopRunning()

            if let preparedAnalyzer {
                await preparedAnalyzer.cancelAndFinishNow()
            }

            reset(sessionID: sessionID)
            throw error
        }
    }

    func stop(sessionID: UUID) async throws -> String {
        try requireActiveSession(sessionID)
        guard let analyzer, let analysisTask else {
            throw PipelineError.notRunning
        }

        // Normal stop is not cancellation. Stop capture, then release the
        // provider/session so its analyzer input sequence can terminate and the
        // analyzer can consume everything that was already captured.
        provider?.captureSession.stopRunning()
        provider = nil

        do {
            let lastSampleTime = try await analysisTask.value
            try requireActiveSession(sessionID)

            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            if let resultTask {
                try await resultTask.value
            }

            try requireActiveSession(sessionID)

            // Apple documents that a volatile result is not guaranteed to be
            // reissued as final. Keep the latest volatile segment if no later
            // final result replaced it.
            let final = join(finalizedText, volatileText)
            reset(sessionID: sessionID)
            return final
        } catch {
            await analyzer.cancelAndFinishNow()
            reset(sessionID: sessionID)
            throw error
        }
    }

    func cancel(sessionID: UUID) async {
        guard activeSessionID == sessionID else { return }

        provider?.captureSession.stopRunning()
        provider = nil
        analysisTask?.cancel()
        resultTask?.cancel()

        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }

        reset(sessionID: sessionID)
    }

    private func makeTranscriber(locale requestedLocale: Locale) async throws -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw PipelineError.unsupportedLocale
        }

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
        provider = nil
        analyzer = nil
        activeSessionID = nil
        finalizedText = ""
        volatileText = ""
    }

    private func join(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)

        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }
}
