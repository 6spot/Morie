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
    let setup = PermissionSetupController(
        locale: Locale(identifier: "zh-CN")
    )
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
                forKey: CapturePersonalizer.enabledDefaultsKey
            ) as? Bool
            ?? true
        let savedCorrectionSuggestionsEnabled =
            defaults.bool(
                forKey:
                    PostInsertionLearningController
                        .dictionarySuggestionsDefaultsKey
            )
        let savedExpressionLearningEnabled =
            defaults.bool(
                forKey: ExpressionProfileStore.enabledDefaultsKey
            )
        let savedSoundFeedbackEnabled =
            defaults.object(
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

        let notifyRuntime = {
            ControlCenterProcessBridge.notifySharedStateChanged()
        }
        dictionary?.onPersistentChange = notifyRuntime
        memory?.onPersistentChange = notifyRuntime
        expressionProfile?.onPersistentChange = notifyRuntime

        installProcessObservers()

        Task { @MainActor [weak self] in
            await self?.prepare()
        }

        refreshICloudSyncState()

        Diagnostics.record(
            "ControlCenterProcess",
            "Lightweight controller initialized; pid=\(ProcessInfo.processInfo.processIdentifier)"
        )
    }

    var canStartCapture: Bool {
        !capabilities.isBootstrapping
            && setup.isReady
            && captureStore != nil
    }

    var canCompleteSetup: Bool {
        !capabilities.isBootstrapping
            && !setup.isBusy
    }

    var isCaptureActive: Bool {
        false
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

    func bootstrap(
        completingSetup: Bool = false
    ) async {
        ControlCenterProcessBridge.requestBootstrap()
        await prepare()
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
            forKey: CapturePersonalizer.enabledDefaultsKey
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
            forKey: ExpressionProfileStore.enabledDefaultsKey
        )
        notifyRuntimeOfSharedStateChange()
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        preferences.soundFeedbackEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: CaptureSoundFeedback.enabledDefaultsKey
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

    private func prepare() async {
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

        Diagnostics.recordMemory(
            "control-center-lightweight-ready"
        )
    }

    private func installProcessObservers() {
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
}
