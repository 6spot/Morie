import AppKit
import Foundation

@MainActor
final class AppController {
    enum ControllerError: LocalizedError {
        case runtimeUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .runtimeUnavailable(let message): message
            }
        }
    }

    let runtime = AppRuntimeController()
    let capabilities = AppCapabilityController()
    let preferences: AppPreferencesController
    let setup: PermissionSetupController
    let refinementModels: RefinementModelPresentationController
    let refinementPrompts: RefinementPromptPresentationController
    let applicationContextInspector = ApplicationContextInspectionStore()
    let dictionary: DictionaryPresentationStore
    let memory: MemoryPresentationStore

    private let client: MorieRuntimeClient
    private var snapshotTask: Task<Void, Never>?
    private var snapshotCanStartCapture = false
    private var snapshotCanCompleteSetup = false
    private var snapshotIsCaptureActive = false
    private var usageMetrics: MorieUsageMetricsDTO?

    init() {
        let client = MorieRuntimeClient()
        self.client = client

        preferences = AppPreferencesController(
            captureShortcut: .defaultValue,
            audioRetentionDays: 7,
            inputRefinementEnabled: true,
            personalMemoryEnabled: true,
            correctionSuggestionsEnabled: false,
            expressionLearningEnabled: false,
            soundFeedbackEnabled: true,
            iCloudSyncEnabled: false,
            iCloudSyncState: .off
        )

        refinementModels = RefinementModelPresentationController(client: client)
        refinementPrompts = RefinementPromptPresentationController(client: client)
        dictionary = DictionaryPresentationStore(client: client)
        memory = MemoryPresentationStore(client: client)

        setup = PermissionSetupController(
            inspect: {
                do {
                    let snapshot = try await client.snapshot()
                    return Self.permissionChecks(snapshot.permissionChecks)
                } catch {
                    return []
                }
            },
            requestPermission: { requirement in
                try? await client.performPermissionAction(
                    Self.requirementRaw(requirement)
                )
            },
            openSettings: { requirement in
                try? await client.performPermissionAction(
                    Self.requirementRaw(requirement)
                )
            }
        )

        runtime.state = .checking
        capabilities.isBootstrapping = true

        snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.connectRuntime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.refreshRuntimeSnapshot(silently: true)
            }
        }
    }

    deinit {
        snapshotTask?.cancel()
    }

    var statusTitle: String {
        switch runtime.state {
        case .checking: "正在连接 Morie Runtime…"
        case .blocked(let reason): reason
        case .ready: "Morie 已就绪"
        case .recording: "正在录音…"
        case .stopping: "正在结束录音…"
        case .finalizing: "正在完成语音识别…"
        case .refining: "正在润色…"
        case .delivering: "正在输入文字…"
        case .failed(let reason): reason
        }
    }

    var statusDetail: String? { capabilities.setupError }
    var canStartCapture: Bool { snapshotCanStartCapture }
    var canCompleteSetup: Bool { snapshotCanCompleteSetup }
    var isCaptureActive: Bool { snapshotIsCaptureActive }

    func startCaptureOnly() {
        Task {
            do {
                try await client.startCaptureOnly()
                await refreshRuntimeSnapshot(silently: true)
            } catch {
                applyConnectionFailure(error)
            }
        }
    }

    func makeControlCenterHistoryController() -> CaptureHistoryController {
        CaptureHistoryController(
            client: client,
            runtimeState: { [weak self] in
                self?.isCaptureActive ?? false
            }
        )
    }

    func controlCenterUsageMetrics() async throws -> MorieUsageMetricsDTO {
        if let usageMetrics { return usageMetrics }
        let snapshot = try await client.snapshot()
        apply(snapshot)
        guard let usageMetrics = snapshot.usageMetrics else {
            throw ControllerError.runtimeUnavailable(
                "Morie Runtime 暂时无法读取使用统计。"
            )
        }
        return usageMetrics
    }

    func bootstrap(completingSetup: Bool = false) async {
        do {
            try await client.bootstrap(completingSetup: completingSetup)
            await refreshRuntimeSnapshot(silently: false)
        } catch {
            applyConnectionFailure(error)
        }
    }

    func refreshPermissions() async {
        await refreshRuntimeSnapshot(silently: false)
        await setup.refresh()
    }

    func setAudioRetentionDays(_ days: Int) {
        mutateSettings(.init(action: .audioRetentionDays, intValue: days))
    }

    func setInputRefinementEnabled(_ enabled: Bool) {
        mutateSettings(.init(
            action: .inputRefinementEnabled,
            boolValue: enabled
        ))
    }

    func setPersonalMemoryEnabled(_ enabled: Bool) {
        mutateSettings(.init(
            action: .personalMemoryEnabled,
            boolValue: enabled
        ))
    }

    func setCorrectionSuggestionsEnabled(_ enabled: Bool) {
        mutateSettings(.init(
            action: .correctionSuggestionsEnabled,
            boolValue: enabled
        ))
    }

    func setExpressionLearningEnabled(_ enabled: Bool) {
        mutateSettings(.init(
            action: .expressionLearningEnabled,
            boolValue: enabled
        ))
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        mutateSettings(.init(
            action: .soundFeedbackEnabled,
            boolValue: enabled
        ))
    }

    func setCaptureShortcut(_ shortcut: CaptureShortcut) {
        mutateSettings(.init(
            action: .captureShortcut,
            stringValue: shortcut.rawValue
        ))
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        mutateSettings(.init(
            action: .iCloudSyncEnabled,
            boolValue: enabled
        ))
    }

    func refreshICloudSyncState() {
        mutateSettings(.init(action: .refreshICloud))
    }

    func clearExpressionProfile() {
        Task {
            do {
                apply(try await client.clearExpressionProfile())
            } catch {
                applyConnectionFailure(error)
            }
        }
    }

    func factoryReset() async throws {
        try await client.factoryReset()
        NSApplication.shared.terminate(nil)
    }

    private func connectRuntime() async {
        do {
            try client.ensureRegistered()
            await refreshRuntimeSnapshot(silently: false)
        } catch {
            applyConnectionFailure(error)
        }
    }

    private func mutateSettings(_ mutation: MorieSettingsMutationDTO) {
        Task {
            do {
                apply(try await client.mutateSettings(mutation))
            } catch {
                applyConnectionFailure(error)
            }
        }
    }

    private func refreshRuntimeSnapshot(silently: Bool) async {
        do {
            apply(try await client.snapshot())
        } catch {
            if !silently {
                applyConnectionFailure(error)
            }
        }
    }

    private func applyConnectionFailure(_ error: Error) {
        snapshotCanStartCapture = false
        snapshotCanCompleteSetup = false
        snapshotIsCaptureActive = false
        capabilities.isBootstrapping = false
        capabilities.setupError = error.localizedDescription
        runtime.state = .failed("Morie Runtime 暂不可用")
    }

    private func apply(_ snapshot: MorieRuntimeSnapshotDTO) {
        snapshotCanStartCapture = snapshot.canStartCapture
        snapshotCanCompleteSetup = snapshot.canCompleteSetup
        snapshotIsCaptureActive = snapshot.isCaptureActive
        usageMetrics = snapshot.usageMetrics

        runtime.transcript = snapshot.transcript
        switch snapshot.phase {
        case "checking": runtime.state = .checking
        case "blocked":
            runtime.state = .blocked(
                snapshot.reason ?? "Morie Runtime 尚未就绪。"
            )
        case "ready": runtime.state = .ready
        case "recording": runtime.state = .recording
        case "stopping": runtime.state = .stopping
        case "finalizing": runtime.state = .finalizing
        case "refining": runtime.state = .refining
        case "delivering": runtime.state = .delivering
        case "failed":
            runtime.state = .failed(
                snapshot.reason ?? "Morie Runtime 发生错误。"
            )
        default:
            runtime.state = .failed("未知 Runtime 状态。")
        }

        capabilities.isBootstrapping = snapshot.isBootstrapping
        capabilities.setupError = snapshot.setupError
        capabilities.needsSetup = snapshot.permissionChecks
            .contains { $0.state != "ready" }

        if let name = snapshot.speechBackendName,
           let locale = snapshot.speechLocaleIdentifier {
            capabilities.speechBackend = SpeechBackendPresentation(
                displayName: name,
                localeIdentifier: locale,
                isFallback: snapshot.speechIsFallback
            )
        } else {
            capabilities.speechBackend = nil
        }

        let settings = snapshot.settings
        preferences.captureShortcut =
            CaptureShortcut(rawValue: settings.captureShortcut)
            ?? .defaultValue
        preferences.audioRetentionDays = settings.audioRetentionDays
        preferences.inputRefinementEnabled = settings.inputRefinementEnabled
        preferences.personalMemoryEnabled = settings.personalMemoryEnabled
        preferences.correctionSuggestionsEnabled =
            settings.correctionSuggestionsEnabled
        preferences.expressionLearningEnabled =
            settings.expressionLearningEnabled
        preferences.soundFeedbackEnabled = settings.soundFeedbackEnabled
        preferences.iCloudSyncEnabled = settings.iCloudSyncEnabled
        preferences.iCloudSyncState = Self.iCloudState(settings)

        refinementModels.apply(settings)
        refinementPrompts.apply(settings)
        setup.replaceChecks(Self.permissionChecks(snapshot.permissionChecks))
    }

    private static func iCloudState(
        _ settings: MorieSettingsSnapshotDTO
    ) -> ICloudSyncState {
        switch settings.iCloudStateKind {
        case "checking": .checking
        case "ready": .ready
        case "restartRequired":
            .restartRequired(settings.iCloudStateDetail)
        case "unavailable":
            .unavailable(settings.iCloudStateDetail)
        default: .off
        }
    }

    private static func permissionChecks(
        _ values: [MoriePermissionCheckDTO]
    ) -> [CapabilityCheck] {
        values.compactMap { value in
            guard let requirement = requirement(value.requirement),
                  let state = capabilityState(value.state)
            else { return nil }
            return CapabilityCheck(
                requirement: requirement,
                state: state,
                detail: value.detail,
                action: value.action.flatMap(capabilityAction)
            )
        }
    }

    private static func requirement(_ raw: String) -> SetupRequirement? {
        switch raw {
        case "appleIntelligence": .appleIntelligence
        case "speechTranscription": .speechTranscription
        case "microphone": .microphone
        case "speechRecognition": .speechRecognition
        case "accessibility": .accessibility
        default: nil
        }
    }

    private static func requirementRaw(
        _ value: SetupRequirement
    ) -> String {
        switch value {
        case .appleIntelligence: "appleIntelligence"
        case .speechTranscription: "speechTranscription"
        case .microphone: "microphone"
        case .speechRecognition: "speechRecognition"
        case .accessibility: "accessibility"
        }
    }

    private static func capabilityState(
        _ raw: String
    ) -> CapabilityCheck.State? {
        switch raw {
        case "ready": .ready
        case "notDetermined": .notDetermined
        case "denied": .denied
        case "restricted": .restricted
        case "unavailable": .unavailable
        default: nil
        }
    }

    private static func capabilityAction(
        _ raw: String
    ) -> CapabilityCheck.Action? {
        switch raw {
        case "requestPermission": .requestPermission
        case "openSettings": .openSettings
        default: nil
        }
    }
}

@MainActor
final class RefinementModelPresentationController: ObservableObject {
    @Published private(set) var mode: RefinementModelMode = .local
    @Published private(set) var cloudBaseURL = ""
    @Published private(set) var cloudModelName = ""
    @Published private(set) var settingsMessage: String?

    private(set) var modelName = "Apple Foundation Models"
    private(set) var modelDetail = "SystemLanguageModel.default · Runtime"
    private(set) var runtimeModelStatus = "正在连接…"
    private(set) var configurationStatusTitle = "待配置"

    private let client: MorieRuntimeClient

    init(client: MorieRuntimeClient) {
        self.client = client
    }

    func apply(_ settings: MorieSettingsSnapshotDTO) {
        mode = RefinementModelMode(rawValue: settings.refinementMode) ?? .local
        cloudBaseURL = settings.cloudBaseURL
        cloudModelName = settings.cloudModelName
        modelName = settings.refinementModelName
        modelDetail = settings.refinementModelDetail
        runtimeModelStatus = settings.refinementModelStatus
        configurationStatusTitle = settings.cloudConfigurationStatus
    }

    func modelStatusTitle(inputRefinementEnabled: Bool) -> String {
        inputRefinementEnabled ? runtimeModelStatus : "已关闭"
    }

    func setMode(_ mode: RefinementModelMode) {
        self.mode = mode
        Task {
            _ = await mutate(
                .init(
                    action: .refinementMode,
                    stringValue: mode.rawValue
                )
            )
        }
    }

    @discardableResult
    func saveCloudConfiguration(
        baseURL: String,
        modelName: String,
        apiKey: String
    ) async -> Bool {
        await mutate(.init(
            action: .saveCloudConfiguration,
            baseURL: baseURL,
            modelName: modelName,
            apiKey: apiKey
        ))
    }

    @discardableResult
    func clearCloudAPIKey() async -> Bool {
        await mutate(.init(action: .clearCloudAPIKey))
    }

    private func mutate(
        _ request: MorieSettingsMutationDTO
    ) async -> Bool {
        do {
            let snapshot = try await client.mutateSettings(request)
            apply(snapshot.settings)
            settingsMessage = nil
            return true
        } catch {
            settingsMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
final class RefinementPromptPresentationController: ObservableObject {
    @Published private(set) var instructions = ""
    @Published private(set) var settingsMessage: String?
    private(set) var isDefault = true

    private let client: MorieRuntimeClient

    init(client: MorieRuntimeClient) {
        self.client = client
    }

    func apply(_ settings: MorieSettingsSnapshotDTO) {
        instructions = settings.refinementInstructions
        isDefault = settings.refinementPromptIsDefault
    }

    @discardableResult
    func save(_ value: String) async -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            settingsMessage = "提示词不能为空。"
            return false
        }
        return await mutate(
            .init(action: .savePrompt, stringValue: normalized)
        )
    }

    @discardableResult
    func restoreDefault() async -> Bool {
        await mutate(.init(action: .restoreDefaultPrompt))
    }

    private func mutate(
        _ request: MorieSettingsMutationDTO
    ) async -> Bool {
        do {
            let snapshot = try await client.mutateSettings(request)
            apply(snapshot.settings)
            settingsMessage = nil
            return true
        } catch {
            settingsMessage = error.localizedDescription
            return false
        }
    }
}
