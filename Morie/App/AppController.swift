import AppKit
import Foundation
import FoundationModels

@MainActor
final class AppController {
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

    let processRole: MorieProcessRole
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

    private let captureStore: CaptureStore?
    private let personalizer: CapturePersonalizer?
    private let postInsertionLearning: PostInsertionLearningController?
    private let persistenceError: Error?
    private let cloudSyncStartupError: Error?

    private var hotkey: PushToTalkHotkey?
    private var audioMaintenanceTask: Task<Void, Never>?
    private var lastPresentedFailure: String?
    private var iCloudStatusTask: Task<Void, Never>?
    private var distributedObservers: [NSObjectProtocol] = []

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
        cloudSyncStartupError: Error? = nil,
        processRole: MorieProcessRole = .current
    ) {
        self.processRole = processRole
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

        let notifyFeatureDataChange = {
            if processRole == .runtime {
                ControlCenterProcessBridge
                    .notifyControlCenterSharedDataChanged()
            } else {
                ControlCenterProcessBridge.notifySharedStateChanged()
            }
        }
        dictionary?.onPersistentChange = notifyFeatureDataChange
        memory?.onPersistentChange = notifyFeatureDataChange
        expressionProfile?.onPersistentChange =
            notifyFeatureDataChange

        if processRole == .runtime {
            captureStore?.onHistoryChange = {
                ControlCenterProcessBridge
                    .notifyControlCenterHistoryChanged()
            }
        }

        if let cloudSyncStartupError {
            Diagnostics.record(
                "iCloud",
                "Managed CloudKit store failed to open; using local store: \(cloudSyncStartupError.localizedDescription)",
                level: .error
            )
        }

        refinementModels.setLocalModelStatusTitle(
            Self.localModelStatusTitle()
        )

        Diagnostics.record(
            "App",
            "Morie controller initialized; role=\(processRole); pid=\(ProcessInfo.processInfo.processIdentifier); \(AppBuildIdentity.current.logValue)"
        )
        DevelopmentDiagnostics.recordEnvironment()

        if processRole == .runtime {
            installRuntimeProcessObservers()
            Task { @MainActor [weak self] in
                await self?.bootstrap()
            }
        } else {
            installControlCenterProcessObservers()
            Task { @MainActor [weak self] in
                await self?.prepareControlCenterProcess()
            }
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
        if processRole == .controlCenter {
            return !capabilities.isBootstrapping
                && setup.isReady
                && captureStore != nil
        }

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
        processRole == .runtime && captureSession.isActive
    }

    func setAudioRetentionDays(_ days: Int) {
        let value = min(max(days, 1), 365)

        if processRole == .controlCenter {
            UserDefaults.standard.set(
                value,
                forKey: CaptureStore.audioRetentionDaysDefaultsKey
            )
            preferences.audioRetentionDays = value
            notifyRuntimeOfSharedStateChange()
            return
        }

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
        if processRole == .runtime {
            captureSession.inputRefinementEnabled = enabled
        }
        UserDefaults.standard.set(
            enabled,
            forKey: CapturePersonalizer.enabledDefaultsKey
        )
        notifyRuntimeOfSharedStateChange()
    }

    func setPersonalMemoryEnabled(_ enabled: Bool) {
        preferences.personalMemoryEnabled = enabled
        PersonalMemorySettings.setEnabled(enabled)
        if processRole == .runtime {
            memoryLearning?.setEnabled(enabled)
        }
        notifyRuntimeOfSharedStateChange()
    }

    func setCorrectionSuggestionsEnabled(_ enabled: Bool) {
        preferences.correctionSuggestionsEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey:
                PostInsertionLearningController
                    .dictionarySuggestionsDefaultsKey
        )
        if processRole == .runtime {
            captureSession.correctionSuggestionsEnabled = enabled

            if !enabled
                && !preferences.expressionLearningEnabled {
                postInsertionLearning?.stop()
            }
        }
        notifyRuntimeOfSharedStateChange()
    }

    func setExpressionLearningEnabled(_ enabled: Bool) {
        preferences.expressionLearningEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: ExpressionProfileStore.enabledDefaultsKey
        )
        if processRole == .runtime {
            captureSession.expressionLearningEnabled = enabled

            if !enabled
                && !preferences.correctionSuggestionsEnabled {
                postInsertionLearning?.stop()
            }
        }
        notifyRuntimeOfSharedStateChange()
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        preferences.soundFeedbackEnabled = enabled
        if processRole == .runtime {
            captureSession.soundFeedbackEnabled = enabled
        }
        UserDefaults.standard.set(
            enabled,
            forKey: CaptureSoundFeedback.enabledDefaultsKey
        )
        notifyRuntimeOfSharedStateChange()
    }

    func clearExpressionProfile() {
        do {
            try expressionProfile?.clear()
            notifyRuntimeOfSharedStateChange()
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
        if processRole == .controlCenter {
            ControlCenterProcessBridge.requestFactoryReset()
            NSApplication.shared.terminate(nil)
            return
        }

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
            notifyRuntimeOfSharedStateChange()
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
                self.notifyRuntimeOfSharedStateChange()

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
        if processRole == .controlCenter {
            ControlCenterProcessBridge.requestCaptureOnly()
            return
        }
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
        if processRole == .controlCenter {
            ControlCenterProcessBridge.requestBootstrap()
            await prepareControlCenterProcess()
            return
        }

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
            refinementModels.setLocalModelStatusTitle(
                Self.localModelStatusTitle()
            )
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
            if let backend =
                await captureSession.preparedSpeechBackend() {
                capabilities.speechBackend =
                    SpeechBackendPresentation(
                        displayName: backend.displayName,
                        localeIdentifier:
                            backend.localeIdentifier,
                        isFallback: backend.isFallback
                    )
            } else {
                capabilities.speechBackend = nil
            }

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

        if processRole == .runtime,
           captureSession.hasActiveCapture {
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

        if processRole == .controlCenter {
            notifyRuntimeOfSharedStateChange()
            return
        }

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

    func notifyRuntimeOfSharedStateChange() {
        guard processRole == .controlCenter else { return }
        ControlCenterProcessBridge.notifySharedStateChanged()
    }

    private func prepareControlCenterProcess() async {
        await setup.refresh()

        if setup.isReady {
            capabilities.needsSetup = false
            capabilities.setupError = nil
            runtime.state = .ready
        } else {
            capabilities.needsSetup = true
            runtime.state = .blocked(
                setup.firstIssue?.detail
                    ?? "请先完成设备与权限检查。"
            )
        }

        Diagnostics.record(
            "ControlCenterProcess",
            "Presentation process prepared; setupReady=\(setup.isReady)"
        )
        Diagnostics.recordMemory("control-center-process-ready")
    }

    private func installRuntimeProcessObservers() {
        let center = DistributedNotificationCenter.default()

        distributedObservers.append(
            center.addObserver(
                forName: .morieRuntimeSharedStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reloadSharedStateFromPersistence()
                    self?.refreshFeatureStoresAfterExternalChange()
                }
            }
        )

        distributedObservers.append(
            center.addObserver(
                forName: .morieRuntimeStartCaptureOnlyRequest,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.startCaptureOnly()
                }
            }
        )

        distributedObservers.append(
            center.addObserver(
                forName: .morieRuntimeBootstrapRequest,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.bootstrap(completingSetup: true)
                }
            }
        )

        distributedObservers.append(
            center.addObserver(
                forName: .morieRuntimeFactoryResetRequest,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    do {
                        try await self?.factoryReset()
                    } catch {
                        Diagnostics.record(
                            "ControlCenterProcess",
                            "Runtime factory reset request failed: \(error.localizedDescription)",
                            level: .error
                        )
                    }
                }
            }
        )

        distributedObservers.append(
            center.addObserver(
                forName: .morieControlCenterWillTerminate,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    Diagnostics.recordMemory(
                        "runtime-after-control-center-close"
                    )
                    try? await Task.sleep(for: .seconds(1))
                    Diagnostics.recordMemory(
                        "runtime-after-control-center-close+1s"
                    )
                }
            }
        )
    }

    private func installControlCenterProcessObservers() {
        let center = DistributedNotificationCenter.default()

        distributedObservers.append(
            center.addObserver(
                forName: .morieControlCenterSharedDataChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshFeatureStoresAfterExternalChange()
                }
            }
        )

        distributedObservers.append(
            center.addObserver(
                forName: .morieControlCenterHistoryChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.captureStore?
                        .refreshHistoryAfterExternalChange()
                }
            }
        )

        distributedObservers.append(
            center.addObserver(
                forName: .morieControlCenterRouteRequest,
                object: nil,
                queue: .main
            ) { notification in
                guard ControlCenterProcessBridge.route(
                    from: notification
                ) == .settings else {
                    return
                }

                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .morieShowSettings,
                        object: nil
                    )
                    NSApplication.shared.activate()
                }
            }
        )
    }

    private func refreshFeatureStoresAfterExternalChange() {
        dictionary?.refreshAfterExternalChange()
        memory?.refreshAfterExternalChange()
        expressionProfile?.refreshAfterExternalChange()
    }

    private func reloadSharedStateFromPersistence() {
        guard processRole == .runtime else { return }

        let defaults = UserDefaults.standard

        let shortcut =
            defaults.string(forKey: CaptureShortcut.defaultsKey)
                .flatMap(CaptureShortcut.init(rawValue:))
                ?? CaptureShortcut.defaultValue
        if shortcut != preferences.captureShortcut {
            setCaptureShortcut(shortcut)
        }

        let audioRetentionDays = CaptureStore.audioRetentionDays
        if audioRetentionDays != preferences.audioRetentionDays {
            do {
                try captureStore?.setAudioRetentionDays(
                    audioRetentionDays
                )
                preferences.audioRetentionDays =
                    audioRetentionDays
            } catch {
                Diagnostics.record(
                    "CaptureStore",
                    "Could not apply Control Center audio retention change: \(error.localizedDescription)",
                    level: .warning
                )
            }
        }

        let inputRefinementEnabled =
            defaults.object(
                forKey: CapturePersonalizer.enabledDefaultsKey
            ) as? Bool
            ?? true
        preferences.inputRefinementEnabled =
            inputRefinementEnabled
        captureSession.inputRefinementEnabled =
            inputRefinementEnabled

        let personalMemoryEnabled =
            PersonalMemorySettings.isEnabled
        preferences.personalMemoryEnabled =
            personalMemoryEnabled
        memoryLearning?.setEnabled(
            personalMemoryEnabled
        )

        let correctionSuggestionsEnabled =
            defaults.bool(
                forKey:
                    PostInsertionLearningController
                        .dictionarySuggestionsDefaultsKey
            )
        preferences.correctionSuggestionsEnabled =
            correctionSuggestionsEnabled
        captureSession.correctionSuggestionsEnabled =
            correctionSuggestionsEnabled

        let expressionLearningEnabled =
            defaults.bool(
                forKey: ExpressionProfileStore.enabledDefaultsKey
            )
        preferences.expressionLearningEnabled =
            expressionLearningEnabled
        captureSession.expressionLearningEnabled =
            expressionLearningEnabled

        let soundFeedbackEnabled =
            defaults.object(
                forKey: CaptureSoundFeedback.enabledDefaultsKey
            ) as? Bool
            ?? true
        preferences.soundFeedbackEnabled =
            soundFeedbackEnabled
        captureSession.soundFeedbackEnabled =
            soundFeedbackEnabled

        let iCloudSyncEnabled = ICloudSyncSettings.isEnabled
        preferences.iCloudSyncEnabled = iCloudSyncEnabled
        if iCloudSyncEnabled {
            preferences.iCloudSyncState =
                captureStore?.cloudSyncEnabled == true
                ? .ready
                : .restartRequired(
                    "已开启，重启 Morie 后开始 iCloud 同步。"
                )
        } else {
            preferences.iCloudSyncState =
                captureStore?.cloudSyncEnabled == true
                ? .restartRequired(
                    "已关闭，重启 Morie 后停止 iCloud 同步。"
                )
                : .off
        }

        refinementModels.reloadPersistedConfiguration()
        refinementPrompts.reloadPersistedInstructions()

        Diagnostics.record(
            "ControlCenterProcess",
            "Runtime reloaded shared Control Center state"
        )
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

    private static func localModelStatusTitle() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可用"
        case .unavailable(.modelNotReady):
            return "模型准备中"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple 智能未开启"
        case .unavailable(.deviceNotEligible):
            return "设备不支持"
        case .unavailable:
            return "暂不可用"
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

        NSApplication.shared.activate()
        alert.runModal()
    }
}
