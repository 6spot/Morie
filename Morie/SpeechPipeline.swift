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
    private var levelTask: Task<Void, Never>?
    private var finalizedText = ""
    private var volatileText = ""

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
        onTranscript: @escaping @Sendable (UUID, String) -> Void,
        onAudioLevel: @escaping @Sendable (UUID, Double) -> Void
    ) async throws {
        guard activeSessionID == nil else { throw PipelineError.alreadyRunning }
        activeSessionID = sessionID
        finalizedText = ""
        volatileText = ""

        let session = label(sessionID)
        Diagnostics.record("Speech", "Pipeline start requested for \(session)")

        var preparedProvider: CaptureInputSequenceProvider?
        var preparedAnalyzer: SpeechAnalyzer?

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

            let provider = try await CaptureInputSequenceProvider.providerWithSession(
                from: microphone,
                compatibleWith: [transcriber],
                priority: .userInitiated
            )
            preparedProvider = provider
            try requireActiveSession(sessionID)
            Diagnostics.record("Speech", "CaptureInputSequenceProvider created for \(session)")

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
                        Diagnostics.record(
                            "Speech",
                            "Final result for \(session); segmentCharacters=\(text.count), accumulatedCharacters=\(finalizedText.count)"
                        )
                    } else {
                        volatileText = text
                        Diagnostics.record(
                            "Speech",
                            "Volatile result for \(session); characters=\(text.count)"
                        )
                    }

                    onTranscript(sessionID, join(finalizedText, volatileText))
                }

                Diagnostics.record("Speech", "Transcriber result stream ended for \(session)")
            }

            analysisTask = Task {
                Diagnostics.record("Speech", "Analyzer sequence started for \(session)")
                let lastSampleTime = try await analyzer.analyzeSequence(analyzerInputs)
                Diagnostics.record(
                    "Speech",
                    "Analyzer sequence ended for \(session); lastSampleTime=\(String(describing: lastSampleTime))"
                )
                return lastSampleTime
            }

            provider.captureSession.startRunning()
            Diagnostics.record("Speech", "AVCaptureSession startRunning called for \(session)")
            try requireActiveSession(sessionID)

            levelTask = Task { [sessionID, onAudioLevel] in
                await self.pollAudioLevels(sessionID: sessionID, onAudioLevel: onAudioLevel)
            }
            Diagnostics.record("Speech", "Native microphone level polling started for \(session)")
        } catch {
            Diagnostics.record("Speech", "Pipeline start failed for \(session): \(error.localizedDescription)", level: .error)
            preparedProvider?.captureSession.stopRunning()
            levelTask?.cancel()
            levelTask = nil

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

        let session = label(sessionID)
        Diagnostics.record("Speech", "Normal stop started for \(session)")

        levelTask?.cancel()
        levelTask = nil
        provider?.captureSession.stopRunning()
        provider = nil
        Diagnostics.record("Speech", "Capture session stopped and provider released for \(session)")

        do {
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

            let final = join(finalizedText, volatileText)
            Diagnostics.record("Speech", "Normal stop completed for \(session); finalCharacters=\(final.count)")
            reset(sessionID: sessionID)
            return final
        } catch {
            Diagnostics.record("Speech", "Normal stop failed for \(session): \(error.localizedDescription)", level: .error)
            await analyzer.cancelAndFinishNow()
            reset(sessionID: sessionID)
            throw error
        }
    }

    func cancel(sessionID: UUID) async {
        guard activeSessionID == sessionID else {
            Diagnostics.record("Speech", "Cancel ignored for stale session \(label(sessionID))", level: .warning)
            return
        }

        let session = label(sessionID)
        Diagnostics.record("Speech", "Cancelling pipeline for \(session)", level: .warning)

        levelTask?.cancel()
        levelTask = nil
        provider?.captureSession.stopRunning()
        provider = nil
        analysisTask?.cancel()
        resultTask?.cancel()

        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }

        reset(sessionID: sessionID)
        Diagnostics.record("Speech", "Pipeline cancelled/reset for \(session)", level: .warning)
    }

    private func pollAudioLevels(
        sessionID: UUID,
        onAudioLevel: @escaping @Sendable (UUID, Double) -> Void
    ) async {
        var smoothedLevel = 0.0

        while !Task.isCancelled,
              activeSessionID == sessionID,
              let provider
        {
            var peakAveragePower: Float = -60

            for connection in provider.captureAudioDataOutput.connections {
                for channel in connection.audioChannels {
                    let power = channel.averagePowerLevel
                    if power.isFinite {
                        peakAveragePower = max(peakAveragePower, power)
                    }
                }
            }

            let normalized = Self.normalizedPowerLevel(peakAveragePower)
            smoothedLevel = smoothedLevel * 0.65 + normalized * 0.35
            onAudioLevel(sessionID, smoothedLevel)

            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
    }

    private static func normalizedPowerLevel(_ decibels: Float) -> Double {
        let floor: Double = -60
        let value = min(max(Double(decibels), floor), 0)
        let normalized = (value - floor) / -floor
        return pow(normalized, 1.35)
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

        levelTask?.cancel()
        analysisTask?.cancel()
        resultTask?.cancel()
        levelTask = nil
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

    private func label(_ sessionID: UUID) -> String {
        String(sessionID.uuidString.prefix(8))
    }
}
