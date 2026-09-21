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
        let applicationContextRequest: ApplicationContextCaptureRequest?
        let inputRefinementEnabled: Bool
        let refinementConfiguration: RefinementConfiguration
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
    var correctionSuggestionsEnabled: Bool
    var expressionLearningEnabled: Bool
    var soundFeedbackEnabled: Bool

    private let speech = SpeechPipeline()
    private let applicationContextCollector = ApplicationContextCollector()
    private let applicationContextInspector: ApplicationContextInspectionStore?
    private let soundFeedback = CaptureSoundFeedback()
    private let injector = TextInjector()
    private let hud = CaptureHUDController()
    private let captureStore: CaptureStore?
    private let history: CaptureHistoryController?
    private let dictionary: DictionaryStore?
    private let personalizer: CapturePersonalizer?
    private let postInsertionLearning: PostInsertionLearningController?
    private let memoryLearning: MemoryLearningController?
    private let resolveRefinementConfiguration: (RefinementConfiguration) -> RefinementConfiguration
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
    private var applicationContextTask: Task<Void, Never>?
    private var activeApplicationContext: ApplicationContextSnapshot?
    private var activeApplicationContextWords: [String] = []
    private var finishRequestedAt: ContinuousClock.Instant?

    init(
        captureStore: CaptureStore?,
        history: CaptureHistoryController?,
        dictionary: DictionaryStore?,
        personalizer: CapturePersonalizer?,
        postInsertionLearning: PostInsertionLearningController?,
        memoryLearning: MemoryLearningController?,
        applicationContextInspector: ApplicationContextInspectionStore? = nil,
        inputRefinementEnabled: Bool,
        resolveRefinementConfiguration: @escaping (RefinementConfiguration) -> RefinementConfiguration = { $0 },
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
        self.applicationContextInspector = applicationContextInspector
        self.inputRefinementEnabled = inputRefinementEnabled
        self.resolveRefinementConfiguration = resolveRefinementConfiguration
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

    func start(
        deliveryMode: CaptureDeliveryMode,
        refinementConfiguration: RefinementConfiguration
    ) {
        guard !isActive, let captureStore else { return }

        let sessionID = UUID()
        let acceptedAt = Date()
        let contextApplication = deliveryMode == .currentApp
            ? NSWorkspace.shared.frontmostApplication
            : nil
        let applicationContextRequest = contextApplication.map {
            ApplicationContextCaptureRequest(
                application: ApplicationIdentity(
                    name: $0.localizedName,
                    bundleIdentifier: $0.bundleIdentifier
                ),
                processIdentifier: Int32($0.processIdentifier),
                capturedAt: acceptedAt
            )
        }
        let sessionContext = CaptureSessionContext(
            id: sessionID,
            deliveryMode: deliveryMode,
            locale: speechLocale,
            dictionaryWords: (try? dictionary?.speechHints()) ?? [],
            applicationContextRequest: applicationContextRequest,
            inputRefinementEnabled: inputRefinementEnabled,
            refinementConfiguration: refinementConfiguration,
            correctionSuggestionsEnabled: correctionSuggestionsEnabled,
            expressionLearningEnabled: expressionLearningEnabled,
            soundFeedbackEnabled: soundFeedbackEnabled,
            acceptedAt: acceptedAt
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
        DevelopmentDiagnostics.record(
            "Capture",
            captureID: sessionID,
            "start; mode=\(sessionContext.deliveryMode.rawValue); locale=\(sessionContext.locale.identifier); refinement=\(sessionContext.inputRefinementEnabled); correctionSuggestions=\(sessionContext.correctionSuggestionsEnabled); expressionLearning=\(sessionContext.expressionLearningEnabled); sound=\(sessionContext.soundFeedbackEnabled); targetApp=\(contextApplication?.localizedName ?? "none"); targetBundle=\(contextApplication?.bundleIdentifier ?? "none"); targetPID=\(contextApplication?.processIdentifier ?? 0); refinementMode=\(sessionContext.refinementConfiguration.model.mode.rawValue); cloudHost=\(sessionContext.refinementConfiguration.model.cloudURL?.host ?? "none"); cloudModel=\(sessionContext.refinementConfiguration.model.trimmedCloudModelName.isEmpty ? "none" : sessionContext.refinementConfiguration.model.trimmedCloudModelName); apiKeyConfigured=\(!sessionContext.refinementConfiguration.model.cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
        )
        DevelopmentDiagnostics.list(
            "Dictionary",
            captureID: sessionID,
            label: "speechHints",
            sessionContext.dictionaryWords
        )
        beginApplicationContextCapture(for: sessionContext)
        Diagnostics.recordMemory("capture-start \(label(sessionID))")

        captureStartTask = Task { @MainActor [weak self] in
            await self?.startCapture(sessionID: sessionID)
        }
    }

    private func beginApplicationContextCapture(
        for sessionContext: CaptureSessionContext
    ) {
        guard let request = sessionContext.applicationContextRequest else {
            return
        }

        applicationContextTask?.cancel()
        activeApplicationContext = nil
        activeApplicationContextWords = []
        let sessionID = sessionContext.id
        applicationContextTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let context = await self.applicationContextCollector.capture(
                request,
                captureID: sessionID
            )
            guard !Task.isCancelled,
                  self.activeCaptureID == sessionID,
                  self.activeSessionContext?.id == sessionID
            else {
                return
            }

            self.activeApplicationContext = context
            let inspectedHints = ApplicationContextVocabulary.inspect(
                from: context,
                captureID: sessionID
            )
            let applicationContextWords = inspectedHints.map(\.value)
            self.activeApplicationContextWords = applicationContextWords
            self.applicationContextTask = nil

            let contextualHintCount = SpeechContextHints.merged(
                dictionaryWords: sessionContext.dictionaryWords,
                applicationContextWords: applicationContextWords
            ).count
            self.applicationContextInspector?.publish(
                captureID: sessionID,
                context: context,
                hints: inspectedHints,
                dictionaryHintCount: sessionContext.dictionaryWords.count,
                contextualHintCount: contextualHintCount
            )

            DevelopmentDiagnostics.text(
                "ApplicationContext",
                captureID: sessionID,
                label: "selected",
                context.selectedText
            )
            DevelopmentDiagnostics.text(
                "ApplicationContext",
                captureID: sessionID,
                label: "focused",
                context.focusedText
            )
            DevelopmentDiagnostics.text(
                "ApplicationContext",
                captureID: sessionID,
                label: "nearby",
                context.nearbyText
            )
            DevelopmentDiagnostics.list(
                "ApplicationContext",
                captureID: sessionID,
                label: "selectedHints",
                inspectedHints.filter { $0.source == .selected }.map(\.value)
            )
            DevelopmentDiagnostics.list(
                "ApplicationContext",
                captureID: sessionID,
                label: "focusedHints",
                inspectedHints.filter { $0.source == .focused }.map(\.value)
            )
            DevelopmentDiagnostics.list(
                "ApplicationContext",
                captureID: sessionID,
                label: "nearbyHints",
                inspectedHints.filter { $0.source == .nearby }.map(\.value)
            )
            DevelopmentDiagnostics.list(
                "ApplicationContext",
                captureID: sessionID,
                label: "mergedSpeechHints",
                SpeechContextHints.merged(
                    dictionaryWords: sessionContext.dictionaryWords,
                    applicationContextWords: applicationContextWords
                )
            )

            let elapsedMilliseconds = max(
                0,
                Int(Date().timeIntervalSince(request.capturedAt) * 1_000)
            )
            Diagnostics.record(
                "ApplicationContext",
                "Capture \(self.label(sessionID)); app=\(context.application.name ?? "unknown") (\(context.application.bundleIdentifier ?? "unknown")); selectedCharacters=\(context.selectedCharacterCount); focusedCharacters=\(context.focusedCharacterCount); nearbyCharacters=\(context.nearbyCharacterCount); extractedHints=\(applicationContextWords.count); collectionMilliseconds=\(elapsedMilliseconds); capturePersistence=false; standardLogRawText=false; devTraceRawText=\(DevelopmentDiagnostics.isEnabled)"
            )
            await self.speech.updateApplicationContextWords(
                applicationContextWords,
                sessionID: sessionID
            )
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
        DevelopmentDiagnostics.record(
            "Stage",
            captureID: sessionID,
            "finishRequested; source=\(source); speechReady=\(speechReadyCaptureID == sessionID); phase=\(String(describing: phase))"
        )
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
        DevelopmentDiagnostics.record(
            "Stage",
            captureID: sessionID,
            level: .warning,
            "cancelRequested; source=\(source); phase=\(String(describing: phase))"
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
                applicationContextWords: activeApplicationContextWords,
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
            if case let SpeechPipeline.PipelineError.recognitionRejected(result) = error {
                await settleRecognitionRejection(sessionID: sessionID, result: result)
                return
            }

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
            DevelopmentDiagnostics.text(
                "Speech",
                captureID: sessionID,
                label: "liveFinal",
                result.transcript
            )
            DevelopmentDiagnostics.record(
                "Audio",
                captureID: sessionID,
                "meaningful=\(String(describing: result.sourceAudio.hasMeaningfulAudio)); durationSeconds=\(result.sourceAudio.duration); sourceFile=\(result.sourceAudio.url.lastPathComponent)"
            )

            var accurateTranscript: String?
            if result.sourceAudio.hasMeaningfulAudio != false
                || !result.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    DevelopmentDiagnostics.list(
                        "SpeechContext",
                        captureID: sessionID,
                        label: "accurateRecognitionHints",
                        SpeechContextHints.merged(
                            dictionaryWords: sessionContext.dictionaryWords,
                            applicationContextWords: activeApplicationContextWords
                        )
                    )
                    accurateTranscript = try await CaptureFileTranscriber.recognize(
                        result.sourceAudio.url,
                        locale: sessionContext.locale,
                        dictionaryWords: sessionContext.dictionaryWords,
                        applicationContextWords: activeApplicationContextWords,
                        captureID: sessionID
                    )
                    Diagnostics.record(
                        "SpeechQuality",
                        "Accurate final re-recognition completed for \(label(sessionID)); liveCharacters=\(result.transcript.count); accurateCharacters=\(accurateTranscript?.count ?? 0)"
                    )
                    DevelopmentDiagnostics.text(
                        "Speech",
                        captureID: sessionID,
                        label: "accurateFinal",
                        accurateTranscript
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
            let preferredRecognitionSource: String
            if let accurateTranscript,
               !accurateTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               finalText == accurateTranscript {
                preferredRecognitionSource = "accurate"
            } else {
                preferredRecognitionSource = "live"
            }
            DevelopmentDiagnostics.record(
                "Speech",
                captureID: sessionID,
                "preferredSource=\(preferredRecognitionSource); liveCharacters=\(result.transcript.count); accurateCharacters=\(accurateTranscript?.count ?? 0); preferredCharacters=\(finalText.count)"
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
            DevelopmentDiagnostics.text(
                "Speech",
                captureID: sessionID,
                label: "preferredFinal",
                finalText
            )

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let disposition = try captureStore.finishEmptyRecognition(
                    for: sessionID,
                    sourceAudio: result.sourceAudio
                )
                history?.captureListDidChange()
                onCancellationEnabledChange?(false)
                resetSessionIdentity()
                setPhase(.idle)
                DevelopmentDiagnostics.record(
                    "Stage",
                    captureID: sessionID,
                    "emptyRecognitionSettled; disposition=\(String(describing: disposition)); hud=\(disposition == .retainedForRetry ? "recognitionFailure" : "noSpeech")"
                )
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
                let resolvedRefinementConfiguration =
                    resolveRefinementConfiguration(
                        sessionContext.refinementConfiguration
                    )
                let refinementConfiguration = RefinementConfiguration(
                    model: resolvedRefinementConfiguration.model,
                    instructions: resolvedRefinementConfiguration.instructions,
                    applicationSpellingCandidates:
                        activeApplicationContextWords
                )
                DevelopmentDiagnostics.list(
                    "RefinementInput",
                    captureID: sessionID,
                    label: "applicationSpellingCandidates",
                    activeApplicationContextWords
                )
                finalText = try await personalizer.refine(
                    sessionID,
                    enabled: sessionContext.inputRefinementEnabled,
                    expressionStyleEnabled: sessionContext.expressionLearningEnabled,
                    otherModelWorkActive: memoryLearning?.isModelBusy == true,
                    configuration: refinementConfiguration
                )
                recordLatency("refinement-final", sessionID: sessionID)
                Diagnostics.recordMemory("refinement-finish \(label(sessionID))")
                try Task.checkCancellation()
                guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }
                onTranscriptChange?(finalText)
                DevelopmentDiagnostics.text(
                    "Refinement",
                    captureID: sessionID,
                    label: "finalAfterRefinement",
                    finalText
                )
            }

            if deliveryMode == .captureOnly {
                try await captureStore.flushPersistence(for: sessionID)
                captureStore.releaseCaptureOwnership(sessionID)
                Diagnostics.record(
                    "CapturePersistence",
                    "Capture-only final state is durable for \(label(sessionID))"
                )
                DevelopmentDiagnostics.record(
                    "Capture",
                    captureID: sessionID,
                    "success; mode=captureOnly; elapsedMs=\(Int(Date().timeIntervalSince(sessionContext.acceptedAt) * 1_000)); finalCharacters=\(finalText.count)"
                )
                completeSuccessfulSession(sessionID, deliveryMode: deliveryMode)
                return
            }

            setPhase(.delivering)
            DevelopmentDiagnostics.record(
                "Stage",
                captureID: sessionID,
                "deliveryStarted; characters=\(finalText.count)"
            )
            hud.showProcessing()

            Diagnostics.record(
                "Delivery",
                "Resolving current keyboard focus for \(finalText.count)-character input"
            )
            DevelopmentDiagnostics.text(
                "Delivery",
                captureID: sessionID,
                label: "text",
                finalText
            )
            let deliveryApplication = try injector.deliver(
                finalText,
                captureID: sessionID
            )
            let deliveredName = deliveryApplication.localizedName
            let deliveredBundle = deliveryApplication.bundleIdentifier
            recordLatency("paste-dispatched", sessionID: sessionID)
            Diagnostics.record(
                "Delivery",
                "Injection completed for \(label(sessionID)); app=\(deliveredName ?? "unknown") (\(deliveredBundle ?? "unknown"))"
            )
            DevelopmentDiagnostics.record(
                "Delivery",
                captureID: sessionID,
                "completed; app=\(deliveredName ?? "unknown"); bundle=\(deliveredBundle ?? "unknown"); pid=\(deliveryApplication.processIdentifier)"
            )

            if !Task.isCancelled, stoppingCaptureID == nil {
                postInsertionLearning?.observeInsertion(
                    finalText,
                    in: deliveryApplication,
                    captureID: sessionID,
                    dictionarySuggestionsEnabled: sessionContext.correctionSuggestionsEnabled,
                    expressionLearningEnabled: sessionContext.expressionLearningEnabled
                )
            }

            try captureStore.markDelivered(
                sessionID,
                applicationName: deliveredName,
                bundleIdentifier: deliveredBundle
            )
            DevelopmentDiagnostics.record(
                "Capture",
                captureID: sessionID,
                "success; elapsedMs=\(Int(Date().timeIntervalSince(sessionContext.acceptedAt) * 1_000)); deliveredCharacters=\(finalText.count)"
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
            if case let SpeechPipeline.PipelineError.recognitionRejected(result) = error {
                await settleRecognitionRejection(sessionID: sessionID, result: result)
                return
            }

            Diagnostics.record(
                "Session",
                "Capture \(label(sessionID)) failed: \(error.localizedDescription)",
                level: .error
            )
            DevelopmentDiagnostics.record(
                "Failure",
                captureID: sessionID,
                level: .error,
                "type=\(DevelopmentDiagnostics.errorType(error)); message=\(error.localizedDescription)"
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
        DevelopmentDiagnostics.record(
            "Stage",
            captureID: sessionID,
            "stopActiveCapture; disposition=\(String(describing: disposition)); startTask=\(startTask != nil); finishTask=\(finishTask != nil)"
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
                    history?.captureListDidChange()
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
        if case let SpeechPipeline.PipelineError.recognitionRejected(result) = error,
           let result {
            preserveSpeechResult(result, for: sessionID)
        }
        let result = await speech.stopImmediately(sessionID: sessionID)
        preserveSpeechResult(result, for: sessionID)
    }

    private func settleRecognitionRejection(
        sessionID: UUID,
        result initialResult: SpeechPipeline.Result?
    ) async {
        guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }

        let result: SpeechPipeline.Result?
        if let initialResult {
            result = initialResult
        } else {
            result = await speech.stopImmediately(sessionID: sessionID)
        }

        do {
            guard let captureStore else {
                throw SessionError.persistenceUnavailable("记录存储尚未初始化。")
            }

            let disposition: CaptureStore.EmptyRecognitionDisposition
            if let result {
                preserveSpeechResult(result, for: sessionID)
                disposition = try captureStore.finishEmptyRecognition(
                    for: sessionID,
                    sourceAudio: result.sourceAudio
                )
                history?.captureListDidChange()
            } else {
                try captureStore.cancel(sessionID)
                disposition = .discarded
            }

            Diagnostics.record(
                "SpeechQuality",
                "Recognition rejection settled for \(label(sessionID)); disposition=\(String(describing: disposition))"
            )
            onCancellationEnabledChange?(false)
            resetSessionIdentity()
            setPhase(.idle)

            if disposition == .retainedForRetry {
                hud.showRecognitionFailure()
            } else {
                hud.showNoSpeech()
            }
        } catch {
            Diagnostics.record(
                "CaptureStore",
                "Could not settle recognition rejection for \(label(sessionID)): \(error.localizedDescription)",
                level: .error
            )
            failSession(sessionID, error: error)
        }
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
        DevelopmentDiagnostics.record(
            "Stage",
            captureID: sessionID,
            "completed; deliveryMode=\(deliveryMode.rawValue); hud=success"
        )
        history?.captureListDidChange()
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
                history?.captureListDidChange()
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
                history?.captureListDidChange()
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
        DevelopmentDiagnostics.record(
            "Stage",
            captureID: sessionID,
            level: .error,
            "failed; errorType=\(DevelopmentDiagnostics.errorType(error)); clipboardFallback=\(preservedOnClipboard)"
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
        applicationContextTask?.cancel()
        applicationContextTask = nil
        activeApplicationContext = nil
        activeApplicationContextWords = []
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
