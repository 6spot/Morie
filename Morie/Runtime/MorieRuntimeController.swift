import AppKit
import Foundation

@MainActor
final class MorieRuntimeController {
    enum ControllerError: LocalizedError {
        case persistenceUnavailable(String)
        case factoryResetUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .persistenceUnavailable(let reason):
                "记录存储不可用：\(reason)"
            case .factoryResetUnavailable(let reason):
                reason
            }
        }
    }

    let runtime = AppRuntimeController()
    let capabilities = AppCapabilityController()
    let preferences: AppPreferencesController

    let memory: MemoryStore?
    let dictionary: DictionaryStore?
    let expressionProfile: ExpressionProfileStore?
    let memoryLearning: MemoryLearningController?

    let setup = PermissionSetupController(
        locale: Locale(identifier: "zh-CN")
    )
    let refinementModels = RefinementModelController()
    let refinementPrompts = RefinementPromptController()
    let applicationContextInspector = ApplicationContextInspectionStore()

    private static let setupCompletedKey = "setup.completed"

    let captureStore: CaptureStore?
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
            dictionary: dictionary,
            personalizer: personalizer,
            postInsertionLearning: postInsertionLearning,
            memoryLearning: memoryLearning,
            applicationContextInspector: applicationContextInspector,
            inputRefinementEnabled: preferences.inputRefinementEnabled,
            resolveRefinementConfiguration: { [weak self] snapshot in
                let model =
                    self?.refinementModels.runtimeConfiguration(
                        for: snapshot.model
                    )
                    ?? snapshot.model
                return RefinementConfiguration(
                    model: model,
                    instructions: snapshot.instructions
                )
            },
            correctionSuggestionsEnabled:
                preferences.correctionSuggestionsEnabled,
            expressionLearningEnabled:
                preferences.expressionLearningEnabled,
            soundFeedbackEnabled: preferences.soundFeedbackEnabled
        )

        session.onPhaseChange = { [weak self] phase in
            self?.applyCapturePhase(phase)
        }
        session.onTranscriptChange = { [weak self] text in
            self?.runtime.transcript = text
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

        memory = captureStore.map {
            MemoryStore(container: $0.container)
        }
        dictionary = captureStore.map {
            DictionaryStore(container: $0.container)
        }
        expressionProfile = captureStore.map {
            ExpressionProfileStore(container: $0.container)
        }

        if let dictionary, let expressionProfile {
            postInsertionLearning =
                PostInsertionLearningController(
                    dictionary: dictionary,
                    expressionProfile: expressionProfile
                )
        } else {
            postInsertionLearning = nil
        }

        let personalizer: CapturePersonalizer?
        if let captureStore,
           let memory,
           let dictionary,
           let expressionProfile {
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

        let savedPersonalMemoryEnabled =
            PersonalMemorySettings.isEnabled
        let savedShortcut = UserDefaults.standard
            .string(forKey: CaptureShortcut.defaultsKey)
            .flatMap(CaptureShortcut.init(rawValue:))
            ?? CaptureShortcut.defaultValue
        let savedInputRefinementEnabled =
            UserDefaults.standard.object(
                forKey: CapturePersonalizer.enabledDefaultsKey
            ) as? Bool
            ?? true
        let savedCorrectionSuggestionsEnabled =
            UserDefaults.standard.bool(
                forKey:
                    PostInsertionLearningController
                        .dictionarySuggestionsDefaultsKey
            )
        let savedExpressionLearningEnabled =
            UserDefaults.standard.bool(
                forKey: ExpressionProfileStore.enabledDefaultsKey
            )
        let savedSoundFeedbackEnabled =
            UserDefaults.standard.object(
                forKey: CaptureSoundFeedback.enabledDefaultsKey
            ) as? Bool
            ?? true
        let savedICloudSyncEnabled = ICloudSyncSettings.isEnabled

        let initialICloudSyncState: ICloudSyncState
        if cloudSyncStartupError != nil {
            initialICloudSyncState = .unavailable(
                "iCloud 同步未能启动，当前继续使用本地数据。"
            )
        } else if savedICloudSyncEnabled {
            initialICloudSyncState =
                captureStore?.cloudSyncEnabled == true
                ? .checking
                : .restartRequired(
                    "已开启，重启 Morie 后开始 iCloud 同步。"
                )
        } else {
            initialICloudSyncState =
                captureStore?.cloudSyncEnabled == true
                ? .restartRequired(
                    "已关闭，重启 Morie 后停止 iCloud 同步。"
                )
                : .off
        }

        preferences = AppPreferencesController(
            captureShortcut: savedShortcut,
            audioRetentionDays: CaptureStore.audioRetentionDays,
            inputRefinementEnabled: savedInputRefinementEnabled,
            personalMemoryEnabled: savedPersonalMemoryEnabled,
            correctionSuggestionsEnabled:
                savedCorrectionSuggestionsEnabled,
            expressionLearningEnabled:
                savedExpressionLearningEnabled,
            soundFeedbackEnabled: savedSoundFeedbackEnabled,
            iCloudSyncEnabled: savedICloudSyncEnabled,
            iCloudSyncState: initialICloudSyncState
        )

        memoryLearning = memory.map {
            MemoryLearningController(
                store: $0,
                enabled: savedPersonalMemoryEnabled,
                canUseModel: {
                    personalizer?.isModelBusy != true
                }
            )
        }

        if let cloudSyncStartupError {
            Diagnostics.record(
                "iCloud",
                "Managed CloudKit store failed to open; using local store: \(cloudSyncStartupError.localizedDescription)",
                level: .error
            )
        }

        Diagnostics.record(
            "App",
            "Morie Runtime controller initialized; \(AppBuildIdentity.current.logValue); launch bootstrap scheduled"
        )
        DevelopmentDiagnostics.recordEnvironment()

        Task { @MainActor [weak self] in
            await self?.bootstrap()
        }

        refreshICloudSyncState()
    }

    var statusTitle: String {
        switch runtime.state {
        case .checking:
            "正在准备 Morie"
        case .blocked:
            "需要完成设置"
        case .ready:
            setup.isReady ? "可以开始录音" : "需要完成设置"
        case .recording:
            "正在聆听…"
        case .stopping:
            "正在停止…"
        case .finalizing:
            "正在完成识别…"
        case .refining:
            "正在润色…"
        case .delivering:
            "正在输入…"
        case .failed:
            "输入失败"
        }
    }

    var statusDetail: String? {
        switch runtime.state {
        case .blocked(let reason), .failed(let reason):
            reason
        case .ready:
            setup.firstIssue?.detail
        default:
            nil
        }
    }

    var canStartCapture: Bool {
        guard !captureSession.isActive,
              !capabilities.isBootstrapping,
              setup.isReady,
              captureStore != nil else {
            return false
        }

        switch runtime.state {
        case .ready, .failed:
            return true
        default:
            return false
        }
    }

    var canCompleteSetup: Bool {
        !isCaptureActive
            && !capabilities.isBootstrapping
            && !setup.isBusy
    }

    var isCaptureActive: Bool {
        captureSession.isActive
    }

    func setAudioRetentionDays(_ days: Int) {
        let value = min(max(days, 1), 365)

        do {
            try captureStore?.setAudioRetentionDays(value)
            preferences.audioRetentionDays = value
        } catch {
            Diagnostics.record(
                "CaptureStore",
                "Could not update audio retention: \(error.localizedDescription)",
                level: .error
            )
        }
    }

    func setInputRefinementEnabled(_ enabled: Bool) {
        preferences.inputRefinementEnabled = enabled
        captureSession.inputRefinementEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: CapturePersonalizer.enabledDefaultsKey
        )
    }

    func setPersonalMemoryEnabled(_ enabled: Bool) {
        preferences.personalMemoryEnabled = enabled
        PersonalMemorySettings.setEnabled(enabled)
        memoryLearning?.setEnabled(enabled)
    }

    func setCorrectionSuggestionsEnabled(_ enabled: Bool) {
        preferences.correctionSuggestionsEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey:
                PostInsertionLearningController
                    .dictionarySuggestionsDefaultsKey
        )
        captureSession.correctionSuggestionsEnabled = enabled

        if !enabled
            && !preferences.expressionLearningEnabled {
            postInsertionLearning?.stop()
        }
    }

    func setExpressionLearningEnabled(_ enabled: Bool) {
        preferences.expressionLearningEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: ExpressionProfileStore.enabledDefaultsKey
        )
        captureSession.expressionLearningEnabled = enabled

        if !enabled
            && !preferences.correctionSuggestionsEnabled {
            postInsertionLearning?.stop()
        }
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        preferences.soundFeedbackEnabled = enabled
        captureSession.soundFeedbackEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: CaptureSoundFeedback.enabledDefaultsKey
        )
    }

    func clearExpressionProfile() {
        do {
            try expressionProfile?.clear()
            Diagnostics.record(
                "ExpressionProfile",
                "Cleared learned expression profile"
            )
        } catch {
            Diagnostics.record(
                "ExpressionProfile",
                "Could not clear learned expression profile",
                level: .error
            )
        }
    }

    func factoryReset() async throws {
        guard !isCaptureActive else {
            throw ControllerError.factoryResetUnavailable(
                "录音或润色进行中，暂时不能恢复出厂设置。"
            )
        }
        guard let captureStore else {
            throw ControllerError.persistenceUnavailable(
                persistenceError?.localizedDescription ?? "记录存储尚未初始化。"
            )
        }

        postInsertionLearning?.stop()
        memoryLearning?.stop()
        await memoryLearning?.waitForCurrentBatch()

        iCloudStatusTask?.cancel()
        iCloudStatusTask = nil
        audioMaintenanceTask?.cancel()
        audioMaintenanceTask = nil

        hotkey?.invalidate()
        hotkey = nil

        try RefinementModelSettings.resetToDefaults()
        RefinementPromptSettings.restoreDefault()

        let defaults = UserDefaults.standard
        [
            Self.setupCompletedKey,
            CaptureShortcut.defaultsKey,
            CaptureStore.audioRetentionDaysDefaultsKey,
            CapturePersonalizer.enabledDefaultsKey,
            PersonalMemorySettings.enabledDefaultsKey,
            PostInsertionLearningController.dictionarySuggestionsDefaultsKey,
            ExpressionProfileStore.enabledDefaultsKey,
            CaptureSoundFeedback.enabledDefaultsKey,
            ICloudSyncSettings.enabledDefaultsKey,
        ].forEach {
            defaults.removeObject(forKey: $0)
        }

        try await captureStore.eraseAllDataForFactoryReset()
        DiagnosticLogStore.shared.clear()

        NSApplication.shared.terminate(nil)
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        iCloudStatusTask?.cancel()
        iCloudStatusTask = nil

        if !enabled {
            ICloudSyncSettings.setEnabled(false)
            preferences.iCloudSyncEnabled = false
            preferences.iCloudSyncState =
                captureStore?.cloudSyncEnabled == true
                ? .restartRequired(
                    "已关闭，重启 Morie 后停止 iCloud 同步。"
                )
                : .off
            return
        }

        preferences.iCloudSyncState = .checking
        iCloudStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await ICloudAccountInspector.status()
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let status):
                if let message =
                    ICloudAccountInspector.unavailableMessage(
                        for: status
                    ) {
                    self.preferences.iCloudSyncEnabled = false
                    self.preferences.iCloudSyncState =
                        .unavailable(message)
                    return
                }

                ICloudSyncSettings.setEnabled(true)
                self.preferences.iCloudSyncEnabled = true
                self.preferences.iCloudSyncState =
                    self.captureStore?.cloudSyncEnabled == true
                    ? .ready
                    : .restartRequired(
                        "已开启，重启 Morie 后开始 iCloud 同步。"
                    )

            case .failure(let error):
                self.preferences.iCloudSyncEnabled = false
                self.preferences.iCloudSyncState =
                    .unavailable(
                        "无法连接 iCloud，请确认账户状态后重试。"
                    )
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

        guard preferences.iCloudSyncEnabled else {
            preferences.iCloudSyncState =
                captureStore?.cloudSyncEnabled == true
                ? .restartRequired(
                    "已关闭，重启 Morie 后停止 iCloud 同步。"
                )
                : .off
            return
        }

        if cloudSyncStartupError != nil {
            preferences.iCloudSyncState = .unavailable(
                "iCloud 同步未能启动，当前继续使用本地数据。"
            )
            return
        }

        preferences.iCloudSyncState = .checking
        iCloudStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await ICloudAccountInspector.status()
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let status):
                if let message =
                    ICloudAccountInspector.unavailableMessage(
                        for: status
                    ) {
                    self.preferences.iCloudSyncState =
                        .unavailable(message)
                } else {
                    self.preferences.iCloudSyncState =
                        self.captureStore?.cloudSyncEnabled == true
                        ? .ready
                        : .restartRequired(
                            "已开启，重启 Morie 后开始 iCloud 同步。"
                        )
                }

            case .failure(let error):
                self.preferences.iCloudSyncState =
                    .unavailable(
                        "无法连接 iCloud，请确认账户状态后重试。"
                    )
                Diagnostics.record(
                    "iCloud",
                    "Account status refresh failed: \(error.localizedDescription)",
                    level: .warning
                )
            }

            self.iCloudStatusTask = nil
        }
    }

    func startCaptureOnly() {
        startNewCapture(deliveryMode: .captureOnly)
    }

    func makeControlCenterHistoryController() -> CaptureHistoryController? {
        captureStore.map {
            CaptureHistoryController(
                store: $0,
                locale: Locale(identifier: "zh-CN")
            )
        }
    }

    func controlCenterUsageMetrics() throws -> CaptureUsageMetricsSnapshot {
        guard let captureStore else {
            throw ControllerError.persistenceUnavailable(
                persistenceError?.localizedDescription
                    ?? "记录存储尚未初始化。"
            )
        }
        return try captureStore.usageMetricsSnapshot()
    }

    func bootstrap(
        completingSetup: Bool = false
    ) async {
        guard !captureSession.isActive,
              !capabilities.isBootstrapping,
              setup.activeRequest == nil else {
            return
        }

        capabilities.isBootstrapping = true
        defer {
            capabilities.isBootstrapping = false
        }

        Diagnostics.record("App", "Bootstrap started")

        runtime.state = .checking
        capabilities.speechBackend = nil
        capabilities.setupError = nil

        memoryLearning?.stop()
        memoryLearning?.setInputActive(true)
        postInsertionLearning?.stop()

        hotkey?.invalidate()
        hotkey = nil

        captureSession.hideHUD()

        do {
            await setup.refresh()
            DevelopmentDiagnostics.list(
                "Capability",
                label: "bootstrapChecks",
                setup.checks.map {
                    "\($0.requirement)=\($0.state)"
                        + ($0.detail.map { "; detail=\($0)" } ?? "")
                }
            )
            try Task.checkCancellation()

            guard runtime.state == .checking else {
                return
            }

            if let persistenceError {
                throw ControllerError.persistenceUnavailable(
                    persistenceError.localizedDescription
                )
            }

            guard captureStore != nil else {
                throw ControllerError.persistenceUnavailable(
                    "记录存储尚未初始化。"
                )
            }

            guard setup.isReady else {
                runtime.state = .blocked(
                    setup.firstIssue?.detail
                        ?? "请先完成使用引导中的设备与权限检查。"
                )
                capabilities.needsSetup = true
                return
            }

            guard completingSetup
                || UserDefaults.standard.bool(
                    forKey: Self.setupCompletedKey
                ) else {
                runtime.state = .blocked(
                    "设备已就绪，请完成使用引导后开始录音。"
                )
                capabilities.needsSetup = true
                return
            }

            try await captureSession.prepareSpeech()
            capabilities.speechBackend =
                await captureSession.preparedSpeechBackend()

            try Task.checkCancellation()
            guard runtime.state == .checking else {
                return
            }

            await setup.refresh()
            try Task.checkCancellation()

            guard runtime.state == .checking else {
                return
            }

            guard setup.isReady else {
                runtime.state = .blocked(
                    setup.firstIssue?.detail
                        ?? "请先完成设备与权限检查。"
                )
                capabilities.needsSetup = true
                return
            }

            try installHotkeyIfNeeded()

            lastPresentedFailure = nil
            UserDefaults.standard.set(
                true,
                forKey: Self.setupCompletedKey
            )

            capabilities.needsSetup = false
            runtime.state = .ready

            memoryLearning?.setInputActive(false)
            memoryLearning?.start()
            startAudioMaintenanceLoopIfNeeded()

            Diagnostics.record(
                "App",
                "Bootstrap complete; Morie is Ready"
            )
            Diagnostics.recordMemory("bootstrap-ready")
        } catch is CancellationError {
            runtime.state = .blocked(
                "准备已取消，可以在使用引导中重试。"
            )
            capabilities.needsSetup = true
            Diagnostics.record(
                "App",
                "Bootstrap cancelled",
                level: .warning
            )
        } catch {
            hotkey?.invalidate()
            hotkey = nil

            let message = error.localizedDescription
            runtime.state = .blocked(message)
            capabilities.setupError = message
            capabilities.needsSetup = true

            Diagnostics.record(
                "App",
                "Bootstrap blocked: \(message)",
                level: .error
            )
        }
    }

    func setCaptureShortcut(
        _ shortcut: CaptureShortcut
    ) {
        guard shortcut
            != preferences.captureShortcut else {
            return
        }

        guard !captureSession.hasActiveCapture else {
            Diagnostics.record(
                "Hotkey",
                "Shortcut change ignored during an active capture",
                level: .warning
            )
            return
        }

        preferences.captureShortcut = shortcut
        UserDefaults.standard.set(
            shortcut.rawValue,
            forKey: CaptureShortcut.defaultsKey
        )

        Diagnostics.record(
            "Hotkey",
            "Shortcut preference changed to \(shortcut.logName)"
        )

        guard canStartCapture else {
            return
        }

        hotkey?.invalidate()
        hotkey = nil

        do {
            try installHotkeyIfNeeded()
        } catch {
            Task { @MainActor [weak self] in
                await self?.handleHotkeyUnavailable(
                    error.localizedDescription
                )
            }
        }
    }

    private func installHotkeyIfNeeded() throws {
        guard hotkey == nil else {
            Diagnostics.record(
                "Hotkey",
                "Controller already owns a hotkey instance"
            )
            return
        }

        let hotkey = PushToTalkHotkey(
            shortcut: preferences.captureShortcut,
            onToggle: { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyToggle()
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    await self?.captureSession.cancel(
                        source: "Escape"
                    )
                }
            },
            onUnavailable: { [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor in
                    await self?.handleHotkeyUnavailable(
                        message
                    )
                }
            }
        )

        try hotkey.start()
        self.hotkey = hotkey

        Diagnostics.record(
            "Hotkey",
            "Controller installed \(preferences.captureShortcut.logName) toggle hotkey"
        )
    }

    private func handleHotkeyToggle() {
        DevelopmentDiagnostics.record(
            "Hotkey",
            "toggleReceived; shortcut=\(preferences.captureShortcut.logName); runtimeState=\(String(describing: runtime.state)); activeCapture=\(captureSession.hasActiveCapture)"
        )
        if captureSession.hasActiveCapture {
            switch captureSession.phase {
            case .recording:
                captureSession.requestFinish(
                    source: preferences.captureShortcut.logName
                )
            case .finalizing, .refining:
                Task { @MainActor [weak self] in
                    await self?.captureSession.cancel(
                        source: "\(self?.preferences.captureShortcut.logName ?? "Shortcut") during processing"
                    )
                }
            default:
                Diagnostics.record(
                    "Session",
                    "Toggle ignored while capture phase=\(String(describing: captureSession.phase))",
                    level: .warning
                )
            }
            return
        }

        switch runtime.state {
        case .ready, .failed:
            startNewCapture(
                deliveryMode: .currentApp
            )

        default:
            Diagnostics.record(
                "Session",
                "Toggle ignored while state=\(String(describing: runtime.state))",
                level: .warning
            )
        }
    }

    private func startNewCapture(
        deliveryMode: CaptureDeliveryMode
    ) {
        guard canStartCapture else {
            DevelopmentDiagnostics.record(
                "Hotkey",
                level: .warning,
                "startBlocked; deliveryMode=\(deliveryMode.rawValue); runtimeState=\(String(describing: runtime.state)); setupReady=\(setup.isReady)"
            )
            return
        }

        lastPresentedFailure = nil

        captureSession.start(
            deliveryMode: deliveryMode,
            refinementConfiguration:
                RefinementConfiguration(
                    model: refinementModels.configuration,
                    instructions:
                        refinementPrompts.instructions
                )
        )
    }

    private func handleHotkeyUnavailable(
        _ message: String
    ) async {
        Diagnostics.record(
            "Hotkey",
            "Global shortcut became unavailable: \(message)",
            level: .error
        )

        runtime.state = .blocked(message)

        hotkey?.invalidate()
        hotkey = nil

        captureSession.hideHUD()
        await captureSession.interrupt(message: message)

        if runtime.state == .blocked(message) {
            captureSession.showFailureHUD()
            capabilities.setupError = message
            capabilities.needsSetup = true
            await setup.refresh()
        }

        Diagnostics.record(
            "UI",
            "Hotkey failure reported without a modal alert so keyboard and pointer interaction remain available",
            level: .warning
        )
    }

    private func applyCapturePhase(
        _ phase: CaptureSessionController.Phase
    ) {
        DevelopmentDiagnostics.record(
            "UIState",
            "capturePhase=\(String(describing: phase)); previousRuntimeState=\(String(describing: runtime.state))"
        )
        switch phase {
        case .idle:
            switch runtime.state {
            case .recording,
                 .stopping,
                 .finalizing,
                 .refining,
                 .delivering:
                runtime.state = .ready

            default:
                break
            }

        case .recording:
            runtime.state = .recording

        case .stopping:
            runtime.state = .stopping

        case .finalizing:
            runtime.state = .finalizing

        case .refining:
            runtime.state = .refining

        case .delivering:
            runtime.state = .delivering

        case .failed(let message):
            runtime.state = .failed(message)
        }
    }

    private func startAudioMaintenanceLoopIfNeeded() {
        guard audioMaintenanceTask == nil else {
            return
        }

        audioMaintenanceTask =
            Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(
                            for: .seconds(
                                24 * 60 * 60
                            )
                        )
                        try Task.checkCancellation()
                    } catch {
                        return
                    }

                    guard let store =
                        self?.captureStore else {
                        return
                    }

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

    private func presentFailure(
        title: String,
        message: String
    ) {
        guard lastPresentedFailure != message else {
            return
        }

        lastPresentedFailure = message

        Diagnostics.record(
            "UI",
            "Presenting alert: \(title) — \(message)",
            level: .warning
        )

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")

        NSApplication.shared.activate(
            ignoringOtherApps: true
        )
        alert.runModal()
    }
}
