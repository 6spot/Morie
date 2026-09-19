import AppKit
import Foundation

@MainActor
final class CaptureSessionController {
    enum Phase: Equatable {
        case idle
        case recording
        case stopping
        case finalizing
        case refining
        case delivering
        case failed(String)
    }

    enum SessionError: LocalizedError {
        case persistenceUnavailable(String)
        case sessionContextUnavailable

        var errorDescription: String? {
            switch self {
            case .persistenceUnavailable(let reason):
                "记录存储不可用：\(reason)"
            case .sessionContextUnavailable:
                "本次录音上下文已失效。"
            }
        }
    }

    private struct CaptureSessionContext: Sendable {
        let id: UUID
        let deliveryMode: CaptureDeliveryMode
        let locale: Locale
        let dictionaryWords: [String]
        let inputRefinementEnabled: Bool
        let refinementModelConfiguration: RefinementModelConfiguration
        let correctionSuggestionsEnabled: Bool
        let expressionLearningEnabled: Bool
        let soundFeedbackEnabled: Bool
        let acceptedAt: Date
    }

    var onPhaseChange: ((Phase) -> Void)?
    var onTranscriptChange: ((String) -> Void)?
    var onCancellationEnabledChange: ((Bool) -> Void)?
    var onPresentFailure: ((String, String) -> Void)?

    var inputRefinementEnabled: Bool
    var refinementModelConfiguration: RefinementModelConfiguration
    var correctionSuggestionsEnabled: Bool
    var expressionLearningEnabled: Bool
    var soundFeedbackEnabled: Bool

    private let speech = SpeechPipeline()
    private let soundFeedback = CaptureSoundFeedback()
    private let injector = TextInjector()
    private let hud = CaptureHUDController()
    private let captureStore: CaptureStore?
    private let history: CaptureHistoryController?
    private let dictionary: DictionaryStore?
    private let personalizer: CapturePersonalizer?
    private let postInsertionLearning: PostInsertionLearningController?
    private let memoryLearning: MemoryLearningController?
    private let speechLocale = Locale(identifier: "zh-CN")

    private(set) var phase: Phase = .idle
    private var activeCaptureID: UUID?
    private var activeSessionContext: CaptureSessionContext?
    private var speechReadyCaptureID: UUID?
    private var finishRequestedCaptureID: UUID?
    private var captureStartTask: Task<Void, Never>?
    private var captureFinishTask: Task<Void, Never>?
    private var captureShutdownTask: Task<Void, Never>?
    private var stoppingCaptureID: UUID?
    private var activeSourceAudioURL: URL?
    private var finishRequestedAt: ContinuousClock.Instant?

    init(
        captureStore: CaptureStore?,
        history: CaptureHistoryController?,
        dictionary: DictionaryStore?,
        personalizer: CapturePersonalizer?,
        postInsertionLearning: PostInsertionLearningController?,
        memoryLearning: MemoryLearningController?,
        inputRefinementEnabled: Bool,
        refinementModelConfiguration: RefinementModelConfiguration = .local,
        correctionSuggestionsEnabled: Bool,
        expressionLearningEnabled: Bool,
        soundFeedbackEnabled: Bool
    ) {
        self.captureStore = captureStore
        self.history = history
        self.dictionary = dictionary
        self.personalizer = personalizer
        self.postInsertionLearning = postInsertionLearning
        self.memoryLearning = memoryLearning
        self.inputRefinementEnabled = inputRefinementEnabled
        self.refinementModelConfiguration = refinementModelConfiguration
        self.correctionSuggestionsEnabled = correctionSuggestionsEnabled
        self.expressionLearningEnabled = expressionLearningEnabled
        self.soundFeedbackEnabled = soundFeedbackEnabled

        hud.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancel(source: "HUD")
            }
        }
        hud.onConfirm = { [weak self] in
            Task { @MainActor in
                self?.requestFinish(source: "HUD")
            }
        }
    }

    var hasActiveCapture: Bool {
        activeCaptureID != nil
    }

    var isActive: Bool {
        activeCaptureID != nil || captureShutdownTask != nil
    }

    func prepareSpeech() async throws {
        Diagnostics.record(
            "App",
            "Capability gate passed; preparing Speech assets for locale \(speechLocale.identifier)"
        )
        try await speech.prepare(locale: speechLocale)
    }

    func preparedSpeechBackend() async -> SpeechRecognitionBackend? {
        await speech.preparedBackendStatus()
    }

    func hideHUD() {
        hud.hide()
    }

    func showFailureHUD() {
        hud.showFailure()
    }

    func start(deliveryMode: CaptureDeliveryMode) {
        guard !isActive, let captureStore else { return }

        let sessionID = UUID()
        let sessionContext = CaptureSessionContext(
            id: sessionID,
            deliveryMode: deliveryMode,
            locale: speechLocale,
            dictionaryWords: (try? dictionary?.speechHints()) ?? [],
            inputRefinementEnabled: inputRefinementEnabled,
            refinementModelConfiguration: refinementModelConfiguration,
            correctionSuggestionsEnabled: correctionSuggestionsEnabled,
            expressionLearningEnabled: expressionLearningEnabled,
            soundFeedbackEnabled: soundFeedbackEnabled,
            acceptedAt: Date()
        )
        let sourceApplication: NSRunningApplication? = sessionContext.deliveryMode == .captureOnly ? .current : nil

        do {
            activeSourceAudioURL = try captureStore.beginVoiceCapture(
                id: sessionID,
                deliveryMode: sessionContext.deliveryMode,
                applicationName: sourceApplication?.localizedName,
                bundleIdentifier: sourceApplication?.bundleIdentifier
            )
        } catch {
            let message = error.localizedDescription
            setPhase(.failed(message))
            Diagnostics.record(
                "CaptureStore",
                "Could not create Capture \(label(sessionID)): \(message)",
                level: .error
            )
            onPresentFailure?("无法保存这次录音", message)
            return
        }

        activeCaptureID = sessionID
        activeSessionContext = sessionContext
        speechReadyCaptureID = nil
        finishRequestedCaptureID = nil
        onTranscriptChange?("")
        setPhase(.recording)
        history?.setInputActive(true)
        postInsertionLearning?.stop()
        memoryLearning?.setInputActive(true)

        onCancellationEnabledChange?(true)
        hud.showRecording()
        if sessionContext.soundFeedbackEnabled {
            soundFeedback.playStart()
        }

        Diagnostics.record(
            "Session",
            "Capture \(label(sessionID)) started; mode=\(sessionContext.deliveryMode.rawValue); deliveryTarget=currentKeyboardFocus; locale=\(sessionContext.locale.identifier); dictionaryHints=\(sessionContext.dictionaryWords.count); acceptedAt=\(sessionContext.acceptedAt.timeIntervalSince1970)"
        )
        Diagnostics.recordMemory("capture-start \(label(sessionID))")

        captureStartTask = Task { @MainActor [weak self] in
            await self?.startCapture(sessionID: sessionID)
        }
    }

    func requestFinish(source: String) {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record(
                "Session",
                "Finish requested from \(source) with no active capture",
                level: .warning
            )
            return
        }

        guard let sessionContext = activeSessionContext, sessionContext.id == sessionID else {
            Diagnostics.record(
                "Session",
                "Finish requested for \(label(sessionID)) without its pinned session context",
                level: .error
            )
            return
        }

        guard phase == .recording, stoppingCaptureID == nil,
              finishRequestedCaptureID != sessionID, captureFinishTask == nil else {
            Diagnostics.record(
                "Session",
                "Duplicate finish request ignored for \(label(sessionID))",
                level: .warning
            )
            return
        }

        finishRequestedCaptureID = sessionID
        finishRequestedAt = ContinuousClock.now
        if sessionContext.soundFeedbackEnabled {
            soundFeedback.playStop()
        }
        setPhase(.finalizing)
        onCancellationEnabledChange?(false)
        hud.showProcessing()
        Diagnostics.record("Session", "Finish requested for \(label(sessionID)) from \(source)")

        if speechReadyCaptureID == sessionID {
            beginFinish(sessionID: sessionID)
        } else {
            Diagnostics.record("Session", "Finish for \(label(sessionID)) is pending Speech startup")
        }
    }

    func cancel(source: String) async {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record(
                "Session",
                "Cancel requested from \(source) with no active capture",
                level: .warning
            )
            return
        }

        guard phase == .recording else {
            Diagnostics.record(
                "Session",
                "Cancel from \(source) ignored while phase=\(String(describing: phase))",
                level: .warning
            )
            return
        }

        Diagnostics.record(
            "Session",
            "Capture \(label(sessionID)) cancelled by \(source)",
            level: .warning
        )
        setPhase(.stopping)
        onCancellationEnabledChange?(false)
        hud.hide()
        await stopActiveCapture(disposition: .discard)
        if phase == .stopping {
            setPhase(.idle)
        }
    }

    func interrupt(message: String) async {
        await stopActiveCapture(disposition: .interrupted(message))
        setPhase(.idle, notify: false)
    }

    private func beginFinish(sessionID: UUID) {
        guard activeCaptureID == sessionID,
              stoppingCaptureID == nil,
              speechReadyCaptureID == sessionID,
              captureFinishTask == nil
        else {
            return
        }

        captureFinishTask = Task { @MainActor [weak self] in
            await self?.finishCapture(sessionID: sessionID)
        }
    }

    private func startCapture(sessionID: UUID) async {
        Diagnostics.record("Speech", "Starting Speech session \(label(sessionID))")

        do {
            await history?.cancelRecognitionAndWait()
            try Task.checkCancellation()
            guard activeCaptureID == sessionID else { throw CancellationError() }
            guard let sessionContext = activeSessionContext, sessionContext.id == sessionID else {
                throw SessionError.sessionContextUnavailable
            }
            guard let sourceAudioURL = activeSourceAudioURL else {
                throw SessionError.persistenceUnavailable("原始录音存储尚未初始化。")
            }

            try await speech.start(
                sessionID: sessionID,
                locale: sessionContext.locale,
                sourceAudioURL: sourceAudioURL,
                dictionaryWords: sessionContext.dictionaryWords,
                onTranscript: { [weak self] resultSessionID, text in
                    Task { @MainActor in
                        guard let self,
                              self.activeCaptureID == resultSessionID,
                              self.stoppingCaptureID != resultSessionID,
                              self.phase == .recording || self.phase == .finalizing else {
                            Diagnostics.record(
                                "Speech",
                                "Ignored stale transcript for \(String(resultSessionID.uuidString.prefix(8)))",
                                level: .warning
                            )
                            return
                        }

                        self.onTranscriptChange?(text)
                        do {
                            try self.captureStore?.updateRecognizedText(text, for: resultSessionID)
                        } catch {
                            Diagnostics.record(
                                "CaptureStore",
                                "Progressive save failed for \(String(resultSessionID.uuidString.prefix(8))): \(error.localizedDescription)",
                                level: .error
                            )
                        }
                        Diagnostics.record(
                            "Speech",
                            "Transcript update for \(String(resultSessionID.uuidString.prefix(8))); characters=\(text.count)"
                        )
                    }
                },
                onAudioLevel: { [weak self] resultSessionID, level in
                    Task { @MainActor in
                        guard let self,
                              self.activeCaptureID == resultSessionID,
                              self.phase == .recording
                        else { return }

                        self.hud.updateAudioLevel(level)
                    }
                },
                onFailure: { [weak self] resultSessionID, message in
                    Task { @MainActor in
                        await self?.handleSpeechFailure(
                            sessionID: resultSessionID,
                            message: message
                        )
                    }
                }
            )

            try Task.checkCancellation()
            guard activeCaptureID == sessionID, stoppingCaptureID == nil else {
                throw CancellationError()
            }

            speechReadyCaptureID = sessionID
            captureStartTask = nil
            Diagnostics.record("Speech", "Speech session \(label(sessionID)) is recording")

            if finishRequestedCaptureID == sessionID {
                Diagnostics.record(
                    "Session",
                    "Applying pending finish request for \(label(sessionID))"
                )
                beginFinish(sessionID: sessionID)
            }
        } catch {
            Diagnostics.record(
                "Speech",
                "Speech start failed for \(label(sessionID)): \(error.localizedDescription)",
                level: .error
            )
            await preserveFailedSpeech(sessionID: sessionID, error: error)
            failSession(sessionID, error: error)
        }
    }

    private func finishCapture(sessionID: UUID) async {
        guard activeCaptureID == sessionID,
              stoppingCaptureID == nil,
              speechReadyCaptureID == sessionID,
              let sessionContext = activeSessionContext,
              sessionContext.id == sessionID
        else {
            Diagnostics.record(
                "Session",
                "Finish ignored because \(label(sessionID)) is no longer active/ready",
                level: .warning
            )
            return
        }

        setPhase(.finalizing)
        hud.showProcessing()
        Diagnostics.record("Speech", "Finalizing Speech session \(label(sessionID))")

        do {
            let result = try await speech.stop(sessionID: sessionID)
            recordLatency("speech-live-final", sessionID: sessionID)
            Diagnostics.recordMemory("speech-stop \(label(sessionID))")

            var accurateTranscript: String?
            if result.sourceAudio.hasMeaningfulAudio != false
                || !result.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    accurateTranscript = try await CaptureFileTranscriber.recognize(
                        result.sourceAudio.url,
                        locale: sessionContext.locale,
                        dictionaryWords: sessionContext.dictionaryWords
                    )
                    Diagnostics.record(
                        "SpeechQuality",
                        "Accurate final re-recognition completed for \(label(sessionID)); liveCharacters=\(result.transcript.count); accurateCharacters=\(accurateTranscript?.count ?? 0)"
                    )
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        throw CancellationError()
                    }
                    Diagnostics.record(
                        "Speech",
                        "Accurate final re-recognition failed for \(label(sessionID)); using progressive transcript: \(error.localizedDescription)",
                        level: .warning
                    )
                }
            } else {
                Diagnostics.record(
                    "SpeechQuality",
                    "Skipped accurate final re-recognition for \(label(sessionID)); source audio was confirmed as no speech"
                )
            }

            var finalText = CaptureFileTranscriber.preferredTranscript(
                live: result.transcript,
                accurate: accurateTranscript
            )
            recordLatency("speech-final", sessionID: sessionID)

            guard let captureStore else {
                throw SessionError.persistenceUnavailable("记录存储尚未初始化。")
            }

            try captureStore.updateRecognizedText(finalText, for: sessionID)
            try captureStore.attachSourceAudio(result.sourceAudio, for: sessionID)
            guard activeCaptureID == sessionID, stoppingCaptureID == nil,
                  !Task.isCancelled else { return }

            onTranscriptChange?(finalText)
            Diagnostics.record("Speech", "Final transcript ready; characters=\(finalText.count)")

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let disposition = try captureStore.finishEmptyRecognition(
                    for: sessionID,
                    sourceAudio: result.sourceAudio
                )
                onCancellationEnabledChange?(false)
                resetSessionIdentity()
                setPhase(.idle)
                if disposition == .retainedForRetry {
                    hud.showRecognitionFailure()
                } else {
                    hud.showNoSpeech()
                }
                return
            }

            let deliveryMode = try captureStore.completeRecognition(finalText, for: sessionID)
            if let personalizer {
                setPhase(.refining)
                finalText = try await personalizer.refine(
                    sessionID,
                    enabled: sessionContext.inputRefinementEnabled,
                    expressionStyleEnabled: sessionContext.expressionLearningEnabled,
                    otherModelWorkActive: memoryLearning?.isModelBusy == true,
                    modelConfiguration: sessionContext.refinementModelConfiguration
                )
                recordLatency("refinement-final", sessionID: sessionID)
                Diagnostics.recordMemory("refinement-finish \(label(sessionID))")
                try Task.checkCancellation()
                guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }
                onTranscriptChange?(finalText)
            }

            if deliveryMode == .captureOnly {
                try await captureStore.flushPersistence(for: sessionID)
                captureStore.releaseCaptureOwnership(sessionID)
                Diagnostics.record(
                    "CapturePersistence",
                    "Capture-only final state is durable for \(label(sessionID))"
                )
                completeSuccessfulSession(sessionID, deliveryMode: deliveryMode)
                return
            }

            setPhase(.delivering)
            hud.showProcessing()

            Diagnostics.record(
                "Delivery",
                "Resolving current keyboard focus for \(finalText.count)-character input"
            )
            let deliveryApplication = try injector.deliver(finalText)
            let deliveredName = deliveryApplication.localizedName
            let deliveredBundle = deliveryApplication.bundleIdentifier
            recordLatency("paste-dispatched", sessionID: sessionID)
            Diagnostics.record(
                "Delivery",
                "Injection completed for \(label(sessionID)); app=\(deliveredName ?? "unknown") (\(deliveredBundle ?? "unknown"))"
            )

            if !Task.isCancelled, stoppingCaptureID == nil {
                postInsertionLearning?.observeInsertion(
                    finalText,
                    in: deliveryApplication,
                    dictionarySuggestionsEnabled: sessionContext.correctionSuggestionsEnabled,
                    expressionLearningEnabled: sessionContext.expressionLearningEnabled
                )
            }

            try captureStore.markDelivered(
                sessionID,
                applicationName: deliveredName,
                bundleIdentifier: deliveredBundle
            )
            completeSuccessfulSession(sessionID, deliveryMode: deliveryMode)
            Task { @MainActor [weak self, weak captureStore] in
                guard let self, let captureStore else { return }
                do {
                    try await captureStore.flushPersistence(for: sessionID)
                    self.memoryLearning?.captureDidComplete(sessionID)
                } catch {
                    Diagnostics.record(
                        "CapturePersistence",
                        "Post-delivery flush failed for \(self.label(sessionID)): \(error.localizedDescription)",
                        level: .error
                    )
                }
            }
        } catch {
            Diagnostics.record(
                "Session",
                "Capture \(label(sessionID)) failed: \(error.localizedDescription)",
                level: .error
            )
            await preserveFailedSpeech(sessionID: sessionID, error: error)
            failSession(sessionID, error: error)
        }
    }

    private func handleSpeechFailure(sessionID: UUID, message: String) async {
        guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }
        Diagnostics.record(
            "Speech",
            "Live recognition failed for \(label(sessionID)): \(message)",
            level: .error
        )
        setPhase(.failed(message))
        await stopActiveCapture(disposition: .interrupted(message))
        if phase == .failed(message) {
            hud.showFailure()
        }
    }

    private enum StopDisposition {
        case discard
        case interrupted(String)
    }

    private func stopActiveCapture(disposition: StopDisposition) async {
        if let captureShutdownTask {
            await captureShutdownTask.value
            return
        }
        guard let sessionID = activeCaptureID else { return }

        stoppingCaptureID = sessionID
        onCancellationEnabledChange?(false)
        hud.hide()
        Diagnostics.record(
            "Session",
            "Stopping active capture \(label(sessionID)); disposition=\(disposition)"
        )

        let startTask = captureStartTask
        let finishTask = captureFinishTask
        startTask?.cancel()
        finishTask?.cancel()

        let shutdownTask = Task { @MainActor in
            let snapshot = await speech.stopImmediately(sessionID: sessionID)
            preserveSpeechResult(snapshot, for: sessionID)
            await startTask?.value
            await finishTask?.value

            do {
                switch disposition {
                case .discard:
                    try captureStore?.cancel(sessionID)
                case .interrupted(let message):
                    try captureStore?.markFailed(sessionID, error: message)
                }
            } catch {
                Diagnostics.record(
                    "CaptureStore",
                    "Capture shutdown save failed: \(error.localizedDescription)",
                    level: .error
                )
            }

            if activeCaptureID == sessionID {
                resetSessionIdentity()
            }
            stoppingCaptureID = nil
        }

        captureShutdownTask = shutdownTask
        await shutdownTask.value
        captureShutdownTask = nil
    }

    private func preserveFailedSpeech(sessionID: UUID, error: Error) async {
        if case let SpeechPipeline.PipelineError.recognitionFailed(_, result) = error {
            preserveSpeechResult(result, for: sessionID)
        }
        let result = await speech.stopImmediately(sessionID: sessionID)
        preserveSpeechResult(result, for: sessionID)
    }

    private func preserveSpeechResult(_ result: SpeechPipeline.Result?, for sessionID: UUID) {
        guard let result else { return }

        if !result.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try captureStore?.updateRecognizedText(result.transcript, for: sessionID)
            } catch {
                Diagnostics.record(
                    "CaptureStore",
                    "Could not preserve interrupted text: \(error.localizedDescription)",
                    level: .error
                )
            }
        }

        do {
            try captureStore?.attachSourceAudio(result.sourceAudio, for: sessionID)
        } catch {
            Diagnostics.record(
                "CaptureStore",
                "Could not preserve interrupted audio metadata: \(error.localizedDescription)",
                level: .error
            )
        }
    }

    private func completeSuccessfulSession(
        _ sessionID: UUID,
        deliveryMode: CaptureDeliveryMode
    ) {
        guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }

        Diagnostics.record("Session", "Capture \(label(sessionID)) completed successfully")
        onCancellationEnabledChange?(false)
        resetSessionIdentity()
        setPhase(.idle)
        hud.showSuccess(deliveryMode: deliveryMode)

        let completedLabel = label(sessionID)
        Diagnostics.recordMemory("capture-complete \(completedLabel)")
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard self?.activeCaptureID == nil else { return }
            Diagnostics.recordMemory("capture-settled \(completedLabel)")
        }
    }

    private func failSession(_ sessionID: UUID, error: Error) {
        guard activeCaptureID == sessionID else { return }

        let message = error.localizedDescription
        let preservedOnClipboard = error is TextInjector.InjectionError
        do {
            if preservedOnClipboard {
                try captureStore?.markDeliveryFailed(sessionID, error: message)
                if let captureStore {
                    Task { @MainActor [weak self, weak captureStore] in
                        guard let self, let captureStore else { return }
                        do {
                            try await captureStore.flushPersistence(for: sessionID)
                            self.memoryLearning?.captureDidComplete(sessionID)
                        } catch {
                            Diagnostics.record(
                                "CapturePersistence",
                                "Clipboard-fallback flush failed for \(self.label(sessionID)): \(error.localizedDescription)",
                                level: .error
                            )
                        }
                    }
                }
            } else if stoppingCaptureID != sessionID {
                try captureStore?.markFailed(sessionID, error: message)
            }
        } catch {
            Diagnostics.record(
                "CaptureStore",
                "Failure state update failed: \(error.localizedDescription)",
                level: .error
            )
        }

        guard stoppingCaptureID != sessionID else { return }

        Diagnostics.record(
            "Session",
            "Capture \(label(sessionID)) failed: \(message)",
            level: .error
        )
        onCancellationEnabledChange?(false)
        resetSessionIdentity()
        setPhase(.failed(message))

        if preservedOnClipboard {
            hud.showClipboardFallback()
            Diagnostics.record(
                "UI",
                "Delivery fallback reported in HUD; modal alert suppressed because transcript is preserved",
                level: .warning
            )
        } else {
            hud.showFailure()
            onPresentFailure?("Morie 输入失败", message)
        }
    }

    private func resetSessionIdentity() {
        activeCaptureID = nil
        activeSessionContext = nil
        activeSourceAudioURL = nil
        speechReadyCaptureID = nil
        finishRequestedCaptureID = nil
        finishRequestedAt = nil
        captureStartTask = nil
        captureFinishTask = nil
        history?.setInputActive(false)
        memoryLearning?.setInputActive(false)
    }

    private func setPhase(_ phase: Phase, notify: Bool = true) {
        self.phase = phase
        if notify {
            onPhaseChange?(phase)
        }
    }

    private func recordLatency(_ stage: String, sessionID: UUID) {
        guard let finishRequestedAt else { return }
        let value = (ContinuousClock.now - finishRequestedAt).components
        let milliseconds = max(
            0,
            Int(Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15)
        )
        Diagnostics.record(
            "InputLatency",
            "Capture \(label(sessionID)) finish→\(stage)=\(milliseconds)ms"
        )
    }

    private func label(_ sessionID: UUID) -> String {
        String(sessionID.uuidString.prefix(8))
    }
}
