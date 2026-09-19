import AppKit
import Combine
import Foundation

@MainActor
final class AppController: ObservableObject {
    enum ControllerError: LocalizedError {
        case persistenceUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .persistenceUnavailable(let reason):
                "记录存储不可用：\(reason)"
            }
        }
    }

    enum State: Equatable {
        case checking
        case blocked(String)
        case ready
        case recording
        case stopping
        case finalizing
        case refining
        case delivering
        case failed(String)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var transcript = ""
    @Published private(set) var captureShortcut: CaptureShortcut
    @Published private(set) var audioRetentionDays: Int
    @Published private(set) var inputRefinementEnabled: Bool
    @Published private(set) var correctionSuggestionsEnabled: Bool
    @Published private(set) var needsSetup = false
    @Published private(set) var setupError: String?
    @Published private(set) var isBootstrapping = false

    let history: CaptureHistoryController?
    let memory: MemoryStore?
    let dictionary: DictionaryStore?
    let memoryLearning: MemoryLearningController?

    let setup = PermissionSetupController(locale: Locale(identifier: "zh-CN"))

    private static let setupCompletedKey = "setup.completed"
    private var setupObservation: AnyCancellable?
    private let speech = SpeechPipeline()
    private let injector = TextInjector()
    private let hud = CaptureHUDController()
    private let captureStore: CaptureStore?
    private let personalizer: CapturePersonalizer?
    private let dictionaryCorrections: DictionaryCorrectionController?
    private let persistenceError: Error?
    private let speechLocale = Locale(identifier: "zh-CN")

    private var hotkey: PushToTalkHotkey?
    private var targetApplication: NSRunningApplication?
    private var targetWindowNumber: CGWindowID?
    private var activeCaptureID: UUID?
    private var speechReadyCaptureID: UUID?
    private var finishRequestedCaptureID: UUID?
    private var captureStartTask: Task<Void, Never>?
    private var captureFinishTask: Task<Void, Never>?
    private var captureShutdownTask: Task<Void, Never>?
    private var stoppingCaptureID: UUID?
    private var activeSourceAudioURL: URL?
    private var lastPresentedFailure: String?

    init(captureStore: CaptureStore?, persistenceError: Error? = nil) {
        self.captureStore = captureStore
        self.persistenceError = persistenceError
        history = captureStore.map { CaptureHistoryController(store: $0, locale: Locale(identifier: "zh-CN")) }
        memory = captureStore.map { MemoryStore(container: $0.container) }
        dictionary = captureStore.map { DictionaryStore(container: $0.container) }
        dictionaryCorrections = dictionary.map { DictionaryCorrectionController(dictionary: $0) }
        let personalizer: CapturePersonalizer?
        if let captureStore, let memory, let dictionary {
            personalizer = CapturePersonalizer(store: captureStore, memory: memory, dictionary: dictionary)
        } else {
            personalizer = nil
        }
        self.personalizer = personalizer
        memoryLearning = memory.map {
            MemoryLearningController(store: $0, canUseModel: { personalizer?.isModelBusy != true })
        }
        let savedShortcut = UserDefaults.standard.string(forKey: CaptureShortcut.defaultsKey)
            .flatMap(CaptureShortcut.init(rawValue:))
        captureShortcut = savedShortcut ?? CaptureShortcut.defaultValue
        audioRetentionDays = CaptureStore.audioRetentionDays
        inputRefinementEnabled = UserDefaults.standard.object(forKey: CapturePersonalizer.enabledDefaultsKey) as? Bool ?? true
        correctionSuggestionsEnabled = UserDefaults.standard.bool(forKey: DictionaryCorrectionController.enabledDefaultsKey)

        hud.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelCaptureFromUser(source: "HUD")
            }
        }
        hud.onConfirm = { [weak self] in
            Task { @MainActor in
                self?.requestFinishActiveCapture(source: "HUD")
            }
        }

        setupObservation = setup.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        Diagnostics.record("App", "Morie controller initialized; launch bootstrap scheduled")
        Task { @MainActor [weak self] in
            await self?.bootstrap()
        }
    }

    var statusTitle: String {
        switch state {
        case .checking: "正在准备 Morie"
        case .blocked: "需要完成设置"
        case .ready: setup.isReady ? "可以开始录音" : "需要完成设置"
        case .recording: "正在聆听…"
        case .stopping: "正在停止…"
        case .finalizing: "正在完成识别…"
        case .refining: "正在润色…"
        case .delivering: "正在输入…"
        case .failed: "输入失败"
        }
    }

    func setAudioRetentionDays(_ days: Int) {
        let value = min(max(days, 1), 365)
        do {
            try captureStore?.setAudioRetentionDays(value)
            audioRetentionDays = value
        } catch {
            Diagnostics.record("CaptureStore", "Could not update audio retention: \(error.localizedDescription)", level: .error)
        }
    }

    func setInputRefinementEnabled(_ enabled: Bool) {
        inputRefinementEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: CapturePersonalizer.enabledDefaultsKey)
    }

    func setCorrectionSuggestionsEnabled(_ enabled: Bool) {
        correctionSuggestionsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DictionaryCorrectionController.enabledDefaultsKey)
        if !enabled { dictionaryCorrections?.stop() }
    }

    var statusDetail: String? {
        switch state {
        case .blocked(let reason), .failed(let reason): reason
        case .ready: setup.firstIssue?.detail
        default: nil
        }
    }

    var canStartCapture: Bool {
        guard activeCaptureID == nil, captureShutdownTask == nil,
              !isBootstrapping, setup.isReady, captureStore != nil else { return false }
        switch state {
        case .ready, .failed: return true
        default: return false
        }
    }

    func recognizeHistoryCapture(_ id: UUID) {
        guard canStartCapture else { return }
        history?.recognizeAgain(id)
    }

    func startCaptureOnly() {
        startNewCapture(deliveryMode: .captureOnly)
    }

    var canCompleteSetup: Bool {
        !isCaptureActive && !isBootstrapping && !setup.isBusy
    }

    var isCaptureActive: Bool { activeCaptureID != nil || captureShutdownTask != nil }

    func bootstrap(completingSetup: Bool = false) async {
        // A setup action must not tear down intentional input. Returning from
        // System Settings calls setup.refresh(), never this startup routine.
        guard activeCaptureID == nil, captureShutdownTask == nil,
              !isBootstrapping, setup.activeRequest == nil else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        Diagnostics.record("App", "Bootstrap started")
        state = .checking
        setupError = nil
        memoryLearning?.stop()
        memoryLearning?.setInputActive(true)
        dictionaryCorrections?.stop()
        hotkey?.invalidate()
        hotkey = nil
        hud.hide()
        history?.pausePlayback()
        await history?.cancelRecognitionAndWait()

        do {
            await setup.refresh()
            try Task.checkCancellation()
            guard state == .checking else { return }
            if let persistenceError {
                throw ControllerError.persistenceUnavailable(persistenceError.localizedDescription)
            }
            guard captureStore != nil else {
                throw ControllerError.persistenceUnavailable("记录存储尚未初始化。")
            }

            guard setup.isReady else {
                let issue = setup.firstIssue
                state = .blocked(issue?.detail ?? "请先完成使用引导中的设备与权限检查。")
                needsSetup = true
                return
            }
            guard completingSetup || UserDefaults.standard.bool(forKey: Self.setupCompletedKey) else {
                state = .blocked("设备已就绪，请完成使用引导后开始录音。")
                needsSetup = true
                return
            }

            Diagnostics.record("App", "Capability gate passed; preparing Speech assets for locale \(speechLocale.identifier)")
            try await speech.prepare(locale: speechLocale)
            try Task.checkCancellation()
            guard state == .checking else { return }

            // Asset preparation can take time; permissions may change while
            // the user is in System Settings. Recheck before enabling input.
            await setup.refresh()
            try Task.checkCancellation()
            guard state == .checking else { return }
            guard setup.isReady else {
                state = .blocked(setup.firstIssue?.detail ?? "请先完成设备与权限检查。")
                needsSetup = true
                return
            }

            try installHotkeyIfNeeded()
            lastPresentedFailure = nil
            UserDefaults.standard.set(true, forKey: Self.setupCompletedKey)
            needsSetup = false
            state = .ready
            memoryLearning?.setInputActive(false)
            memoryLearning?.start()
            Diagnostics.record("App", "Bootstrap complete; Morie is Ready")
        } catch is CancellationError {
            state = .blocked("准备已取消，可以在使用引导中重试。")
            needsSetup = true
            Diagnostics.record("App", "Bootstrap cancelled", level: .warning)
        } catch {
            hotkey?.invalidate()
            hotkey = nil
            let message = error.localizedDescription
            state = .blocked(message)
            setupError = message
            needsSetup = true
            Diagnostics.record("App", "Bootstrap blocked: \(message)", level: .error)
        }
    }

    private func installHotkeyIfNeeded() throws {
        guard hotkey == nil else {
            Diagnostics.record("Hotkey", "Controller already owns a hotkey instance")
            return
        }

        let hotkey = PushToTalkHotkey(
            shortcut: captureShortcut,
            onToggle: { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyToggle()
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    await self?.cancelCaptureFromUser(source: "Escape")
                }
            },
            onUnavailable: { [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor in
                    await self?.handleHotkeyUnavailable(message)
                }
            }
        )

        try hotkey.start()
        self.hotkey = hotkey
        Diagnostics.record("Hotkey", "Controller installed \(captureShortcut.logName) toggle hotkey")
    }

    func setCaptureShortcut(_ shortcut: CaptureShortcut) {
        guard shortcut != captureShortcut else { return }
        guard activeCaptureID == nil else {
            Diagnostics.record("Hotkey", "Shortcut change ignored during an active capture", level: .warning)
            return
        }

        captureShortcut = shortcut
        UserDefaults.standard.set(shortcut.rawValue, forKey: CaptureShortcut.defaultsKey)
        Diagnostics.record("Hotkey", "Shortcut preference changed to \(shortcut.logName)")
        guard canStartCapture else { return }

        hotkey?.invalidate()
        hotkey = nil
        do {
            try installHotkeyIfNeeded()
        } catch {
            Task { @MainActor [weak self] in
                await self?.handleHotkeyUnavailable(error.localizedDescription)
            }
        }
    }

    private func handleHotkeyToggle() {
        if activeCaptureID != nil {
            requestFinishActiveCapture(source: captureShortcut.logName)
            return
        }

        switch state {
        case .ready, .failed:
            startNewCapture(deliveryMode: .currentApp)
        default:
            Diagnostics.record("Session", "Toggle ignored while state=\(String(describing: state))", level: .warning)
        }
    }

    private func startNewCapture(deliveryMode: CaptureDeliveryMode) {
        guard canStartCapture, let captureStore else { return }

        lastPresentedFailure = nil

        let sessionID = UUID()
        let sourceApplication: NSRunningApplication?
        switch deliveryMode {
        case .currentApp:
            sourceApplication = NSWorkspace.shared.frontmostApplication
            targetApplication = sourceApplication
            targetWindowNumber = TextInjector.frontmostWindowNumber(for: targetApplication)
        case .captureOnly:
            sourceApplication = .current
            targetApplication = nil
            targetWindowNumber = nil
        }

        do {
            activeSourceAudioURL = try captureStore.beginVoiceCapture(
                id: sessionID,
                deliveryMode: deliveryMode,
                applicationName: sourceApplication?.localizedName,
                bundleIdentifier: sourceApplication?.bundleIdentifier,
                windowNumber: targetWindowNumber
            )
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            Diagnostics.record("CaptureStore", "Could not create Capture \(label(sessionID)): \(message)", level: .error)
            presentFailure(title: "无法保存这次录音", message: message)
            return
        }

        activeCaptureID = sessionID
        speechReadyCaptureID = nil
        finishRequestedCaptureID = nil
        transcript = ""
        state = .recording
        history?.setInputActive(true)
        dictionaryCorrections?.stop()
        memoryLearning?.setInputActive(true)

        hotkey?.setCancellationEnabled(true)
        hud.showRecording()

        let targetName = targetApplication?.localizedName ?? "unknown"
        let targetBundle = targetApplication?.bundleIdentifier ?? "unknown"
        Diagnostics.record(
            "Session",
            "Capture \(label(sessionID)) started; mode=\(deliveryMode.rawValue); target=\(targetName) (\(targetBundle)); window=\(targetWindowNumber.map(String.init) ?? "unknown"); locale=\(speechLocale.identifier)"
        )

        captureStartTask = Task { @MainActor [weak self] in
            await self?.startCapture(sessionID: sessionID)
        }
    }

    private func requestFinishActiveCapture(source: String) {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record("Session", "Finish requested from \(source) with no active capture", level: .warning)
            return
        }

        guard state == .recording, stoppingCaptureID == nil,
              finishRequestedCaptureID != sessionID, captureFinishTask == nil else {
            Diagnostics.record("Session", "Duplicate finish request ignored for \(label(sessionID))", level: .warning)
            return
        }

        finishRequestedCaptureID = sessionID
        state = .finalizing
        hotkey?.setCancellationEnabled(false)
        hud.showProcessing()
        Diagnostics.record("Session", "Finish requested for \(label(sessionID)) from \(source)")

        if speechReadyCaptureID == sessionID {
            beginFinish(sessionID: sessionID)
        } else {
            Diagnostics.record("Session", "Finish for \(label(sessionID)) is pending Speech startup")
        }
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
            guard let sourceAudioURL = activeSourceAudioURL else {
                throw ControllerError.persistenceUnavailable("原始录音存储尚未初始化。")
            }
            try await speech.start(
                sessionID: sessionID,
                locale: speechLocale,
                sourceAudioURL: sourceAudioURL,
                dictionaryWords: (try? dictionary?.speechHints()) ?? [],
                onTranscript: { [weak self] resultSessionID, text in
                    Task { @MainActor in
                        guard self?.activeCaptureID == resultSessionID,
                              self?.stoppingCaptureID != resultSessionID,
                              self?.state == .recording || self?.state == .finalizing else {
                            Diagnostics.record("Speech", "Ignored stale transcript for \(String(resultSessionID.uuidString.prefix(8)))", level: .warning)
                            return
                        }

                        self?.transcript = text
                        do {
                            try self?.captureStore?.updateRecognizedText(text, for: resultSessionID)
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
                        guard self?.activeCaptureID == resultSessionID,
                              self?.state == .recording
                        else { return }

                        self?.hud.updateAudioLevel(level)
                    }
                },
                onFailure: { [weak self] resultSessionID, message in
                    Task { @MainActor in
                        await self?.handleSpeechFailure(sessionID: resultSessionID, message: message)
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
                Diagnostics.record("Session", "Applying pending finish request for \(label(sessionID))")
                beginFinish(sessionID: sessionID)
            }
        } catch {
            Diagnostics.record("Speech", "Speech start failed for \(label(sessionID)): \(error.localizedDescription)", level: .error)
            await preserveFailedSpeech(sessionID: sessionID, error: error)
            failSession(sessionID, error: error)
        }
    }

    private func finishCapture(sessionID: UUID) async {
        guard activeCaptureID == sessionID,
              stoppingCaptureID == nil,
              speechReadyCaptureID == sessionID
        else {
            Diagnostics.record("Session", "Finish ignored because \(label(sessionID)) is no longer active/ready", level: .warning)
            return
        }

        state = .finalizing
        hud.showProcessing()
        Diagnostics.record("Speech", "Finalizing Speech session \(label(sessionID))")

        do {
            let result = try await speech.stop(sessionID: sessionID)
            var finalText = result.transcript
            guard let captureStore else {
                throw ControllerError.persistenceUnavailable("记录存储尚未初始化。")
            }
            // Persist a late final result even if an interruption has taken over
            // UI/teardown ownership. Only the explicit discard path deletes it.
            try captureStore.updateRecognizedText(finalText, for: sessionID)
            try captureStore.attachSourceAudio(result.sourceAudio, for: sessionID)
            guard activeCaptureID == sessionID, stoppingCaptureID == nil,
                  !Task.isCancelled else { return }

            transcript = finalText
            Diagnostics.record("Speech", "Final transcript ready; characters=\(finalText.count)")

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let disposition = try captureStore.finishEmptyRecognition(for: sessionID, sourceAudio: result.sourceAudio)
                hotkey?.setCancellationEnabled(false)
                resetSessionIdentity()
                state = .ready
                if disposition == .retainedForRetry {
                    hud.showRecognitionFailure()
                } else {
                    hud.hide()
                }
                return
            }

            let deliveryMode = try captureStore.completeRecognition(finalText, for: sessionID)
            if let personalizer {
                state = .refining
                finalText = try await personalizer.refine(
                    sessionID, enabled: inputRefinementEnabled,
                    otherModelWorkActive: memoryLearning?.isModelBusy == true
                )
                // Cancellation/recheck may have taken over while the optional model was running.
                try Task.checkCancellation()
                guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }
                transcript = finalText
            }
            if deliveryMode == .captureOnly {
                completeSuccessfulSession(sessionID, deliveryMode: deliveryMode)
                return
            }

            state = .delivering
            hud.showProcessing()

            let targetName = targetApplication?.localizedName ?? "unknown"
            let targetBundle = targetApplication?.bundleIdentifier ?? "unknown"
            Diagnostics.record("Delivery", "Injecting \(finalText.count) characters into \(targetName) (\(targetBundle))")

            try await injector.deliver(
                finalText,
                to: targetApplication,
                originalWindowNumber: targetWindowNumber
            )
            Diagnostics.record("Delivery", "Injection completed for \(label(sessionID))")
            if correctionSuggestionsEnabled, !Task.isCancelled, stoppingCaptureID == nil {
                dictionaryCorrections?.observeInsertion(finalText, in: targetApplication)
            }
            // Delivery may already have dispatched before cancellation arrived.
            // Record that outcome even when interruption now owns the UI.
            try captureStore.markDelivered(sessionID)
            completeSuccessfulSession(sessionID, deliveryMode: deliveryMode)
        } catch {
            Diagnostics.record("Session", "Capture \(label(sessionID)) failed: \(error.localizedDescription)", level: .error)
            await preserveFailedSpeech(sessionID: sessionID, error: error)
            failSession(sessionID, error: error)
        }
    }

    private func cancelCaptureFromUser(source: String) async {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record("Session", "Cancel requested from \(source) with no active capture", level: .warning)
            return
        }

        guard state == .recording else {
            Diagnostics.record("Session", "Cancel from \(source) ignored while state=\(String(describing: state))", level: .warning)
            return
        }

        Diagnostics.record("Session", "Capture \(label(sessionID)) cancelled by \(source)", level: .warning)
        state = .stopping
        hotkey?.setCancellationEnabled(false)
        hud.hide()
        await stopActiveCapture(disposition: .discard)
        if state == .stopping { state = .ready }
    }

    private func handleHotkeyUnavailable(_ message: String) async {
        Diagnostics.record("Hotkey", "Global shortcut became unavailable: \(message)", level: .error)
        state = .blocked(message)
        hotkey?.invalidate()
        hotkey = nil
        hud.hide()
        await stopActiveCapture(disposition: .interrupted(message))
        if state == .blocked(message) {
            hud.showFailure()
            setupError = message
            needsSetup = true
            await setup.refresh()
        }
        Diagnostics.record(
            "UI",
            "Hotkey failure reported without a modal alert so keyboard and pointer interaction remain available",
            level: .warning
        )
    }

    private func handleSpeechFailure(sessionID: UUID, message: String) async {
        guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }
        Diagnostics.record("Speech", "Live recognition failed for \(label(sessionID)): \(message)", level: .error)
        state = .failed(message)
        await stopActiveCapture(disposition: .interrupted(message))
        if state == .failed(message) { hud.showFailure() }
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
        hotkey?.setCancellationEnabled(false)
        hud.hide()
        Diagnostics.record("Session", "Stopping active capture \(label(sessionID)); disposition=\(disposition)")

        let startTask = captureStartTask
        let finishTask = captureFinishTask
        startTask?.cancel()
        finishTask?.cancel()

        let shutdownTask = Task { @MainActor in
            // Close the writer first. Awaiting the work tasks afterward lets
            // their last text/audio snapshot reach storage before disposition.
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
                Diagnostics.record("CaptureStore", "Capture shutdown save failed: \(error.localizedDescription)", level: .error)
            }

            if activeCaptureID == sessionID { resetSessionIdentity() }
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
                Diagnostics.record("CaptureStore", "Could not preserve interrupted text: \(error.localizedDescription)", level: .error)
            }
        }
        do {
            try captureStore?.attachSourceAudio(result.sourceAudio, for: sessionID)
        } catch {
            Diagnostics.record("CaptureStore", "Could not preserve interrupted audio metadata: \(error.localizedDescription)", level: .error)
        }
    }

    private func completeSuccessfulSession(_ sessionID: UUID, deliveryMode: CaptureDeliveryMode) {
        guard activeCaptureID == sessionID, stoppingCaptureID == nil else { return }
        Diagnostics.record("Session", "Capture \(label(sessionID)) completed successfully")
        hotkey?.setCancellationEnabled(false)
        resetSessionIdentity()
        lastPresentedFailure = nil
        state = .ready
        hud.showSuccess(deliveryMode: deliveryMode)
    }

    private func failSession(_ sessionID: UUID, error: Error) {
        guard activeCaptureID == sessionID else { return }

        let message = error.localizedDescription
        let preservedOnClipboard = error is TextInjector.InjectionError
        do {
            if preservedOnClipboard {
                try captureStore?.markDeliveryFailed(sessionID, error: message)
            } else if stoppingCaptureID != sessionID {
                try captureStore?.markFailed(sessionID, error: message)
            }
        } catch {
            Diagnostics.record("CaptureStore", "Failure state save failed: \(error.localizedDescription)", level: .error)
        }
        guard stoppingCaptureID != sessionID else { return }
        Diagnostics.record("Session", "Capture \(label(sessionID)) failed: \(message)", level: .error)
        hotkey?.setCancellationEnabled(false)
        resetSessionIdentity()
        state = .failed(message)

        if preservedOnClipboard {
            hud.showClipboardFallback()
            Diagnostics.record(
                "UI",
                "Delivery fallback reported in HUD; modal alert suppressed because transcript is preserved",
                level: .warning
            )
        } else {
            hud.showFailure()
            presentFailure(title: "Morie 输入失败", message: message)
        }
    }

    private func resetSessionIdentity() {
        activeCaptureID = nil
        activeSourceAudioURL = nil
        speechReadyCaptureID = nil
        finishRequestedCaptureID = nil
        captureStartTask = nil
        captureFinishTask = nil
        targetApplication = nil
        targetWindowNumber = nil
        history?.setInputActive(false)
        memoryLearning?.setInputActive(false)
    }

    private func presentFailure(title: String, message: String) {
        guard lastPresentedFailure != message else { return }
        lastPresentedFailure = message
        Diagnostics.record("UI", "Presenting alert: \(title) — \(message)", level: .warning)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func label(_ sessionID: UUID) -> String {
        String(sessionID.uuidString.prefix(8))
    }
}
