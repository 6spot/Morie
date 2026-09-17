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

    private var analyzer: SpeechAnalyzer?
    private var provider: CaptureInputSequenceProvider?
    private var resultTask: Task<Void, Error>?
    private var analysisTask: Task<CMTime?, Error>?
    private var finalizedText = ""
    private var volatileText = ""

    func start(
        locale requestedLocale: Locale,
        onTranscript: @escaping @Sendable (String) -> Void
    ) async throws {
        guard analyzer == nil else { throw PipelineError.alreadyRunning }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw PipelineError.noMicrophone
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw PipelineError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }

        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: [transcriber],
            priority: .userInitiated
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        finalizedText = ""
        volatileText = ""
        self.provider = provider
        self.analyzer = analyzer

        resultTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)

                if result.isFinal {
                    finalizedText = join(finalizedText, text)
                    volatileText = ""
                } else {
                    volatileText = text
                }

                onTranscript(join(finalizedText, volatileText))
            }
        }

        provider.captureSession.startRunning()

        analysisTask = Task {
            try await analyzer.analyzeSequence(provider.analyzerInputs)
        }
    }

    func stop() async throws -> String {
        guard let analyzer, let provider, let analysisTask else {
            throw PipelineError.notRunning
        }

        provider.captureSession.stopRunning()

        do {
            if let lastSampleTime = try await analysisTask.value {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                try analyzer.cancelAndFinishNow()
            }

            _ = try await resultTask?.value
            let final = join(finalizedText, volatileText)
            reset()
            return final
        } catch {
            try? analyzer.cancelAndFinishNow()
            reset()
            throw error
        }
    }

    private func reset() {
        analysisTask?.cancel()
        resultTask?.cancel()
        analysisTask = nil
        resultTask = nil
        provider = nil
        analyzer = nil
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
