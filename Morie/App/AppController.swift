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
    @Published private(set) var expressionLearningEnabled: Bool
    @Published private(set) var soundFeedbackEnabled: Bool
    @Published private(set) var iCloudSyncEnabled: Bool
    @Published private(set) var iCloudSyncState: ICloudSyncState
    @Published private(set) var needsSetup = false
    @Published private(set) var setupError: String?
    @Published private(set) var isBootstrapping = false
    @Published private(set) var speechBackend: SpeechRecognitionBackend?

    let history: CaptureHistoryController?
    let memory: MemoryStore?
    let dictionary: DictionaryStore?
    let expressionProfile: ExpressionProfileStore?
    let memoryLearning: MemoryLearningController?

    let setup = PermissionSetupController(locale: Locale(identifier: "zh-CN"))
    let refinementModels = RefinementModelController()
    let refinementPrompts = RefinementPromptController()

    private static let setupCompletedKey = "setup.completed"
    private var setupObservation: AnyCancellable?
    private let captureStore: CaptureStore?
    private let personalizer: CapturePersonalizer?
    private let postInsertionLearning: PostInsertionLearningController?
    private let persistenceError: Error?
    private let cloudSyncStartupError: Error?

    private var hotkey: PushToTalkHotkey?
    private var audioMaintenanceTask: Task<Void, Never>?
    private var lastPresentedFailure: String?
    private var iCloudStatusTask: Task<Void, Never>?

    private lazy var captureSession: CaptureSessionController = {
        let session = CaptureSessionController(
            captureStore: captureStore,
            history: history,
            dictionary: dictionary,
            personalizer: personalizer,
            postInsertionLearning: postInsertionLearning,
            memoryLearning: memoryLearning,
            inputRefinementEnabled: inputRefinementEnabled,
            resolveRefinementConfiguration: { [weak self] snapshot in
                let model = self?.refinementModels.runtimeConfiguration(for: snapshot.model) ?? snapshot.model
                return RefinementConfiguration(model: model, instructions: snapshot.instructions)
            },
            correctionSuggestionsEnabled: correctionSuggestionsEnabled,
            expressionLearningEnabled: expressionLearningEnabled,
            soundFeedbackEnabled: soundFeedbackEnabled
        )
        session.onPhaseChange = { [weak self] phase in
            self?.applyCapturePhase(phase)
        }
        session.onTranscriptChange = { [weak self] text in
            self?.transcript = text
        }
        session.onCancellationEnabledChange = { [weak self] enabled in
            self?.hotkey?.setCancellationEnabled(enabled)
        }
        session.onPresentFailure = { [weak self] title, message in
            self?.presentFailure(title: title, message: message)
        }
        return session
    }()

    init(
        captureStore: CaptureStore?,
        persistenceError: Error? = nil,
        cloudSyncStartupError: Error? = nil
    ) {
        self.captureStore = captureStore
        self.persistenceError = persistenceError
        self.cloudSyncStartupError = cloudSyncStartupError
        history = captureStore.map { CaptureHistoryController(store: $0, locale: Locale(identifier: "zh-CN")) }
        memory = captureStore.map { MemoryStore(container: $0.container) }
        dictionary = captureStore.map { DictionaryStore(container: $0.container) }
        expressionProfile = captureStore.map { ExpressionProfileStore(container: $0.container) }
        if let dictionary, let expressionProfile {
            postInsertionLearning = PostInsertionLearningController(
                dictionary: dictionary,
                expressionProfile: expressionProfile
            )
        } else {
            postInsertionLearning = nil
        }
        let personalizer: CapturePersonalizer?
        if let captureStore, let memory, let dictionary, let expressionProfile {
            personalizer = CapturePersonalizer(
                store: captureStore,
                memory: memory,
                dictionary: dictionary,
                expressionProfile: expressionProfile
            )
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
        correctionSuggestionsEnabled = UserDefaults.standard.bool(
            forKey: PostInsertionLearningController.dictionarySuggestionsDefaultsKey
        )
        expressionLearningEnabled = UserDefaults.standard.bool(forKey: ExpressionProfileStore.enabledDefaultsKey)
        soundFeedbackEnabled = UserDefaults.standard.object(
            forKey: CaptureSoundFeedback.enabledDefaultsKey
        ) as? Bool ?? true
        let savedICloudSyncEnabled = ICloudSyncSettings.isEnabled
        iCloudSyncEnabled = savedICloudSyncEnabled
        if let cloudSyncStartupError {
            iCloudSyncState = .unavailable("iCloud 同步未能启动，当前继续使用本地数据。")
            Diagnostics.record(
                "iCloud",
                "Managed CloudKit store failed to open; using local store: \(cloudSyncStartupError.localizedDescription)",
                level: .error
            )
        } else if savedICloudSyncEnabled {
            iCloudSyncState = captureStore?.cloudSyncEnabled == true
                ? .checking
                : .restartRequired("已开启，重启 Morie 后开始 iCloud 同步。")
        } else {
            iCloudSyncState = captureStore?.cloudSyncEnabled == true
                ? .restartRequired("已关闭，重启 Morie 后停止 iCloud 同步。")
                : .off
        }

        setupObservation = setup.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        Diagnostics.record("App", "Morie controller initialized; launch bootstrap scheduled")
        Task { @MainActor [weak self] in
            await self?.bootstrap()
        }
        refreshICloudSyncState()
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
        captureSession.inputRefinementEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: CapturePersonalizer.enabledDefaultsKey)
    }

    func setCorrectionSuggestionsEnabled(_ enabled: Bool) {
        correctionSuggestionsEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: PostInsertionLearningController.dictionarySuggestionsDefaultsKey
        )
        captureSession.correctionSuggestionsEnabled = enabled
        if !enabled && !expressionLearningEnabled { postInsertionLearning?.stop() }
    }

    func setExpressionLearningEnabled(_ enabled: Bool) {
        expressionLearningEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: ExpressionProfileStore.enabledDefaultsKey)
        captureSession.expressionLearningEnabled = enabled
        if !enabled && !correctionSuggestionsEnabled { postInsertionLearning?.stop() }
    }


    func setSoundFeedbackEnabled(_ enabled: Bool) {
        soundFeedbackEnabled = enabled
        captureSession.soundFeedbackEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: CaptureSoundFeedback.enabledDefaultsKey)
    }

    func clearExpressionProfile() {
        do {
            try expressionProfile?.clear()
            Diagnostics.record("ExpressionProfile", "Cleared learned expression profile")
        } catch {
            Diagnostics.record("ExpressionProfile", "Could not clear learned expression profile", level: .error)
        }
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        iCloudStatusTask?.cancel()
        iCloudStatusTask = nil

        if !enabled {
            ICloudSyncSettings.setEnabled(false)
            iCloudSyncEnabled = false
            iCloudSyncState = captureStore?.cloudSyncEnabled == true
                ? .restartRequired("已关闭，重启 Morie 后停止 iCloud 同步。")
                : .off
            return
        }

        iCloudSyncState = .checking
        iCloudStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await ICloudAccountInspector.status()
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let status):
                if let message = ICloudAccountInspector.unavailableMessage(for: status) {
                    self.iCloudSyncEnabled = false
                    self.iCloudSyncState = .unavailable(message)
                    return
                }
                ICloudSyncSettings.setEnabled(true)
                self.iCloudSyncEnabled = true
                self.iCloudSyncState = self.captureStore?.cloudSyncEnabled == true
                    ? .ready
                    : .restartRequired("已开启，重启 Morie 后开始 iCloud 同步。")
            case .failure(let error):
                self.iCloudSyncEnabled = false
                self.iCloudSyncState = .unavailable("无法连接 iCloud，请确认账户状态后重试。")
                Diagnostics.record(
                    "iCloud",
                    "Account status check failed: \(error.localizedDescription)",
                    level: .warning
                )
            }
            self.iCloudStatusTask = nil
        }
    }

    func refreshICloudSyncState() {
        iCloudStatusTask?.cancel()
        guard iCloudSyncEnabled else {
            iCloudSyncState = captureStore?.cloudSyncEnabled == true
                ? .restartRequired("已关闭，重启 Morie 后停止 iCloud 同步。")
                : .off
            return
        }
        if cloudSyncStartupError != nil {
            iCloudSyncState = .unavailable("iCloud 同步未能启动，当前继续使用本地数据。")
            return
        }

        iCloudSyncState = .checking
        iCloudStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await ICloudAccountInspector.status()
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let status):
                if let message = ICloudAccountInspector.unavailableMessage(for: status) {
                    self.iCloudSyncState = .unavailable(message)
                } else {
                    self.iCloudSyncState = self.captureStore?.cloudSyncEnabled == true
                        ? .ready
                        : .restartRequired("已开启，重启 Morie 后开始 iCloud 同步。")
                }
            case .failure(let error):
                self.iCloudSyncState = .unavailable("无法连接 iCloud，请确认账户状态后重试。")
                Diagnostics.record(
                    "iCloud",
                    "Account status refresh failed: \(error.localizedDescription)",
                    level: .warning
                )
            }
            self.iCloudStatusTask = nil
        }
    }

    var statusDetail: String? {
        switch state {
        case .blocked(let reason), .failed(let reason): reason
        case .ready: setup.firstIssue?.detail
        default: nil
        }
    }

    var canStartCapture: Bool {
        guard !captureSession.isActive,
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

    var isCaptureActive: Bool { captureSession.isActive }

    func bootstrap(completingSetup: Bool = false) async {
        // A setup action must not tear down intentional input. Returning from
        // System Settings calls setup.refresh(), never this startup routine.
        guard !captureSession.isActive,
              !isBootstrapping, setup.activeRequest == nil else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        Diagnostics.record("App", "Bootstrap started")
        state = .checking
        speechBackend = nil
        setupError = nil
        memoryLearning?.stop()
        memoryLearning?.setInputActive(true)
        postInsertionLearning?.stop()
        hotkey?.invalidate()
        hotkey = nil
        captureSession.hideHUD()
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

            try await captureSession.prepareSpeech()
            speechBackend = await captureSession.preparedSpeechBackend()
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
            startAudioMaintenanceLoopIfNeeded()
            Diagnostics.record("App", "Bootstrap complete; Morie is Ready")
            Diagnostics.recordMemory("bootstrap-ready")
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
                    await self?.captureSession.cancel(source: "Escape")
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
        guard !captureSession.hasActiveCapture else {
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
        if captureSession.hasActiveCapture {
            captureSession.requestFinish(source: captureShortcut.logName)
            return
        }

        switch state {
        case .ready, .failed:
            startNewCapture(deliveryMode: .currentApp)
        default:
            Diagnostics.record(
                "Session",
                "Toggle ignored while state=\(String(describing: state))",
                level: .warning
            )
        }
    }

    private func startNewCapture(deliveryMode: CaptureDeliveryMode) {
        guard canStartCapture else { return }
        lastPresentedFailure = nil
        captureSession.start(
            deliveryMode: deliveryMode,
            refinementConfiguration: RefinementConfiguration(
                model: refinementModels.configuration,
                instructions: refinementPrompts.instructions
            )
        )
    }

    private func handleHotkeyUnavailable(_ message: String) async {
        Diagnostics.record("Hotkey", "Global shortcut became unavailable: \(message)", level: .error)
        state = .blocked(message)
        hotkey?.invalidate()
        hotkey = nil
        captureSession.hideHUD()
        await captureSession.interrupt(message: message)
        if state == .blocked(message) {
            captureSession.showFailureHUD()
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

    private func applyCapturePhase(_ phase: CaptureSessionController.Phase) {
        switch phase {
        case .idle:
            switch state {
            case .recording, .stopping, .finalizing, .refining, .delivering:
                state = .ready
            default:
                break
            }
        case .recording:
            state = .recording
        case .stopping:
            state = .stopping
        case .finalizing:
            state = .finalizing
        case .refining:
            state = .refining
        case .delivering:
            state = .delivering
        case .failed(let message):
            state = .failed(message)
        }
    }

    private func startAudioMaintenanceLoopIfNeeded() {
        guard audioMaintenanceTask == nil else { return }
        audioMaintenanceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(24 * 60 * 60))
                    try Task.checkCancellation()
                } catch {
                    return
                }

                guard let store = self?.captureStore else { return }
                do {
                    try store.pruneExpiredAudio()
                } catch {
                    Diagnostics.record(
                        "CaptureStore",
                        "Scheduled audio maintenance failed: \(error.localizedDescription)",
                        level: .warning
                    )
                }
            }
        }
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


}
