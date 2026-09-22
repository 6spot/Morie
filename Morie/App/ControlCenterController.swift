import AppKit
import Foundation

@MainActor
protocol ControlCenterControlling: AnyObject {
    var runtime: AppRuntimeController { get }
    var capabilities: AppCapabilityController { get }
    var preferences: AppPreferencesController { get }
    var setup: PermissionSetupController { get }
    var refinementModels: RefinementModelController { get }
    var refinementPrompts: RefinementPromptController { get }
    var applicationContextInspector: ApplicationContextInspectionStore { get }
    var memory: MemoryStore? { get }
    var dictionary: DictionaryStore? { get }

    var canStartCapture: Bool { get }
    var canCompleteSetup: Bool { get }
    var isCaptureActive: Bool { get }

    func makeControlCenterHistoryController() -> CaptureHistoryController?
    func controlCenterUsageMetrics() throws -> CaptureUsageMetricsSnapshot

    func startCaptureOnly()
    func refreshPermissions() async
    func performPermissionAction(_ requirement: SetupRequirement) async
    func bootstrap(completingSetup: Bool) async
    func factoryReset() async throws

    func setAudioRetentionDays(_ days: Int)
    func setInputRefinementEnabled(_ enabled: Bool)
    func setPersonalMemoryEnabled(_ enabled: Bool)
    func setCorrectionSuggestionsEnabled(_ enabled: Bool)
    func setExpressionLearningEnabled(_ enabled: Bool)
    func setSoundFeedbackEnabled(_ enabled: Bool)
    func setCaptureShortcut(_ shortcut: CaptureShortcut)
    func setICloudSyncEnabled(_ enabled: Bool)
    func refreshICloudSyncState()
    func clearExpressionProfile()
    func notifyRuntimeOfSharedStateChange()
}

extension AppController: ControlCenterControlling {}

@MainActor
final class ControlCenterController: ControlCenterControlling {
    enum ControllerError: LocalizedError {
        case persistenceUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .persistenceUnavailable(let reason):
                reason
            }
        }
    }

    let runtime = AppRuntimeController()
    let capabilities = AppCapabilityController()
    let preferences: AppPreferencesController
    let setup: PermissionSetupController
    let refinementModels = RefinementModelController()
    let refinementPrompts = RefinementPromptController()
    let applicationContextInspector =
        ApplicationContextInspectionStore()

    let memory: MemoryStore?
    let dictionary: DictionaryStore?
    private let expressionProfile: ExpressionProfileStore?
    private let captureStore: CaptureStore?
    private let persistenceError: Error?
    private let cloudSyncStartupError: Error?

    private var distributedObservers: [NSObjectProtocol] = []
    private var iCloudStatusTask: Task<Void, Never>?

    init(
        captureStore: CaptureStore?,
        persistenceError: Error? = nil,
        cloudSyncStartupError: Error? = nil
    ) {
        setup = PermissionSetupController(
            inspect: { [] },
            requestPermission: { _ in },
            openSettings: { _ in }
        )
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

        let defaults = UserDefaults.standard
        let savedPersonalMemoryEnabled =
            PersonalMemorySettings.isEnabled
        let savedShortcut = defaults
            .string(forKey: CaptureShortcut.defaultsKey)
            .flatMap(CaptureShortcut.init(rawValue:))
            ?? CaptureShortcut.defaultValue
        let savedInputRefinementEnabled =
            defaults.object(
                forKey: MoriePreferenceKey.inputRefinementEnabled
            ) as? Bool
            ?? true
        let savedCorrectionSuggestionsEnabled =
            defaults.bool(
                forKey:
                    MoriePreferenceKey.dictionarySuggestionsEnabled
            )
        let savedExpressionLearningEnabled =
            defaults.bool(
                forKey: MoriePreferenceKey.expressionLearningEnabled
            )
        let savedSoundFeedbackEnabled =
            defaults.object(
                forKey: MoriePreferenceKey.soundFeedbackEnabled
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

        let notifyRuntime = {
            ControlCenterProcessBridge.notifySharedStateChanged()
        }
        dictionary?.onPersistentChange = notifyRuntime
        memory?.onPersistentChange = notifyRuntime
        expressionProfile?.onPersistentChange = notifyRuntime

        installProcessObservers()

        runtime.state = .checking
        capabilities.isBootstrapping = true
        ControlCenterProcessBridge.requestRuntimeSnapshot()

        refreshICloudSyncState()

        Diagnostics.record(
            "ControlCenterProcess",
            "Lightweight controller initialized; pid=\(ProcessInfo.processInfo.processIdentifier)"
        )
    }

    var canStartCapture: Bool {
        guard captureStore != nil,
              !capabilities.isBootstrapping else {
            return false
        }
        if case .ready = runtime.state {
            return true
        }
        return false
    }

    var canCompleteSetup: Bool {
        !capabilities.isBootstrapping
            && !setup.isBusy
    }

    var isCaptureActive: Bool {
        switch runtime.state {
        case .recording, .stopping, .finalizing, .refining,
             .delivering:
            return true
        default:
            return false
        }
    }

    func makeControlCenterHistoryController()
        -> CaptureHistoryController? {
        captureStore.map {
            CaptureHistoryController(
                store: $0,
                locale: Locale(identifier: "zh-CN"),
                recognizeFile: { _, _ in
                    throw CaptureStore.StoreError.audioUnavailable
                }
            )
        }
    }

    func controlCenterUsageMetrics()
        throws -> CaptureUsageMetricsSnapshot {
        guard let captureStore else {
            throw ControllerError.persistenceUnavailable(
                persistenceError?.localizedDescription
                    ?? "记录存储尚未初始化。"
            )
        }
        return try captureStore.usageMetricsSnapshot()
    }

    func startCaptureOnly() {
        ControlCenterProcessBridge.requestCaptureOnly()
    }

    func refreshPermissions() async {
        ControlCenterProcessBridge.requestRuntimeSnapshot()
    }

    func performPermissionAction(
        _ requirement: SetupRequirement
    ) async {
        ControlCenterProcessBridge.requestPermissionAction(
            requirement
        )
    }

    func bootstrap(
        completingSetup: Bool = false
    ) async {
        ControlCenterProcessBridge.requestBootstrap()
        capabilities.isBootstrapping = true
        runtime.state = .checking
        ControlCenterProcessBridge.requestRuntimeSnapshot()
    }

    func factoryReset() async throws {
        ControlCenterProcessBridge.requestFactoryReset()
        NSApplication.shared.terminate(nil)
    }

    func setAudioRetentionDays(_ days: Int) {
        let value = min(max(days, 1), 365)
        UserDefaults.standard.set(
            value,
            forKey: CaptureStore.audioRetentionDaysDefaultsKey
        )
        preferences.audioRetentionDays = value
        notifyRuntimeOfSharedStateChange()
    }

    func setInputRefinementEnabled(_ enabled: Bool) {
        preferences.inputRefinementEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: MoriePreferenceKey.inputRefinementEnabled
        )
        notifyRuntimeOfSharedStateChange()
    }

    func setPersonalMemoryEnabled(_ enabled: Bool) {
        preferences.personalMemoryEnabled = enabled
        PersonalMemorySettings.setEnabled(enabled)
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
        notifyRuntimeOfSharedStateChange()
    }

    func setExpressionLearningEnabled(_ enabled: Bool) {
        preferences.expressionLearningEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: MoriePreferenceKey.expressionLearningEnabled
        )
        notifyRuntimeOfSharedStateChange()
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        preferences.soundFeedbackEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: MoriePreferenceKey.soundFeedbackEnabled
        )
        notifyRuntimeOfSharedStateChange()
    }

    func setCaptureShortcut(_ shortcut: CaptureShortcut) {
        guard shortcut != preferences.captureShortcut else {
            return
        }
        preferences.captureShortcut = shortcut
        UserDefaults.standard.set(
            shortcut.rawValue,
            forKey: CaptureShortcut.defaultsKey
        )
        notifyRuntimeOfSharedStateChange()
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
                } else {
                    ICloudSyncSettings.setEnabled(true)
                    self.preferences.iCloudSyncEnabled = true
                    self.preferences.iCloudSyncState =
                        self.captureStore?.cloudSyncEnabled == true
                        ? .ready
                        : .restartRequired(
                            "已开启，重启 Morie 后开始 iCloud 同步。"
                        )
                    self.notifyRuntimeOfSharedStateChange()
                }

            case .failure:
                self.preferences.iCloudSyncEnabled = false
                self.preferences.iCloudSyncState =
                    .unavailable(
                        "无法连接 iCloud，请确认账户状态后重试。"
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
            case .failure:
                self.preferences.iCloudSyncState =
                    .unavailable(
                        "无法连接 iCloud，请确认账户状态后重试。"
                    )
            }

            self.iCloudStatusTask = nil
        }
    }

    func clearExpressionProfile() {
        do {
            try expressionProfile?.clear()
            notifyRuntimeOfSharedStateChange()
        } catch {
            Diagnostics.record(
                "ExpressionProfile",
                "Could not clear learned expression profile",
                level: .error
            )
        }
    }

    func notifyRuntimeOfSharedStateChange() {
        ControlCenterProcessBridge.notifySharedStateChanged()
    }

    private func installProcessObservers() {
        let center = DistributedNotificationCenter.default()

        distributedObservers.append(
            center.addObserver(
                forName: .morieControlCenterRuntimeSnapshot,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let snapshot =
                    ControlCenterProcessBridge.runtimeSnapshot(
                        from: notification
                    ) else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.applyRuntimeSnapshot(snapshot)
                }
            }
        )

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

    private func applyRuntimeSnapshot(
        _ snapshot: ControlCenterRuntimeSnapshot
    ) {
        setup.applyExternalChecks(snapshot.checks)
        capabilities.isBootstrapping =
            snapshot.isBootstrapping
        capabilities.setupError = snapshot.setupError
        capabilities.needsSetup =
            !snapshot.checks.isEmpty && !setup.isReady
        capabilities.speechBackend =
            snapshot.speechBackend
        refinementModels.setLocalModelStatusTitle(
            snapshot.localModelStatusTitle
        )

        if snapshot.isCaptureActive {
            runtime.state = .recording
        } else if snapshot.canStartCapture {
            runtime.state = .ready
        } else if let setupError = snapshot.setupError {
            runtime.state = .blocked(setupError)
        } else {
            runtime.state = .blocked(
                "Morie 运行进程尚未就绪。"
            )
        }

        Diagnostics.recordMemory(
            "control-center-runtime-snapshot"
        )
    }

    private func refreshFeatureStoresAfterExternalChange() {
        dictionary?.refreshAfterExternalChange()
        memory?.refreshAfterExternalChange()
        expressionProfile?.refreshAfterExternalChange()
    }
}
