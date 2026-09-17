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
                            "Final result for \(session); text=\"\(text)\"; accumulated=\"\(finalizedText)\""
                        )
                    } else {
                        volatileText = text
                        Diagnostics.record(
                            "Speech",
                            "Volatile result for \(session); text=\"\(text)\""
                        )
                    }

                    let combined = join(finalizedText, volatileText)
                    Diagnostics.record(
                        "SpeechText",
                        "Session \(session) transcript=\"\(combined)\""
                    )
                    onTranscript(sessionID, combined)
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
            startAudioLevelPolling(
                provider: provider,
                sessionID: sessionID,
                onAudioLevel: onAudioLevel
            )
            try requireActiveSession(sessionID)
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
            Diagnostics.record("Speech", "Normal stop completed for \(session); finalText=\"\(final)\"")
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

    private func makeTranscriber(locale requestedLocale: Locale) async throws -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            Diagnostics.record("Speech", "Unsupported requested locale: \(requestedLocale.identifier)", level: .error)
            throw PipelineError.unsupportedLocale
        }

        Diagnostics.record("Speech", "Resolved Speech locale: \(locale.identifier)")
        return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    private func startAudioLevelPolling(
        provider: CaptureInputSequenceProvider,
        sessionID: UUID,
        onAudioLevel: @escaping @Sendable (UUID, Double) -> Void
    ) {
        levelTask?.cancel()
        let session = label(sessionID)

        levelTask = Task {
            Diagnostics.record("Speech", "Native microphone level polling started for \(session)")
            var sampleCount = 0

            while !Task.isCancelled {
                guard activeSessionID == sessionID else { return }

                let channels = provider.captureSession.connections.flatMap(\.audioChannels)
                let averagePower = channels.map(\.averagePowerLevel).max() ?? -60
                let peakPower = channels.map(\.peakHoldLevel).max() ?? -60
                let normalized = Self.normalizedPower(averagePower)

                // Keep the audio signal raw here. The HUD owns visual shaping/history;
                // pre-smoothing at the capture layer makes normal speech look flat.
                onAudioLevel(sessionID, normalized)

                sampleCount += 1
                if sampleCount.isMultiple(of: 20) {
                    let averageText = String(format: "%.1f", averagePower)
                    let peakText = String(format: "%.1f", peakPower)
                    let normalizedText = String(format: "%.3f", normalized)
                    Diagnostics.record(
                        "Audio",
                        "Meter \(session): channels=\(channels.count), average=\(averageText)dB, peak=\(peakText)dB, normalized=\(normalizedText), captureRunning=\(provider.captureSession.isRunning)"
                    )
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private static func normalizedPower(_ decibels: Float) -> Double {
        let floor: Float = -60
        let clamped = min(max(decibels, floor), 0)
        return Double((clamped - floor) / -floor)
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
