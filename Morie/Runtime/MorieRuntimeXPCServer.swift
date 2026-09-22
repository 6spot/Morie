import Foundation
import SwiftData

final class MorieRuntimeXPCServer: NSObject, NSXPCListenerDelegate {
    private let controller: MorieRuntimeController
    private let listener: NSXPCListener

    init(controller: MorieRuntimeController) {
        self.controller = controller
        listener = NSXPCListener(
            machServiceName: MorieRuntimeIPC.serviceName
        )
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: MorieRuntimeXPCProtocol.self
        )
        newConnection.exportedObject = MorieRuntimeXPCService(
            controller: controller
        )
        newConnection.resume()
        return true
    }
}

private final class MorieRuntimeXPCService: NSObject, MorieRuntimeXPCProtocol {
    private let controller: MorieRuntimeController

    init(controller: MorieRuntimeController) {
        self.controller = controller
    }

    func runtimeSnapshot(reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            reply(self.encodedSnapshot(), nil)
        }
    }

    func startCaptureOnly(reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            guard self.controller.canStartCapture else {
                reply("Morie Runtime 当前还不能开始录音。")
                return
            }
            self.controller.startCaptureOnly()
            reply(nil)
        }
    }

    func bootstrap(
        _ completingSetup: Bool,
        reply: @escaping (String?) -> Void
    ) {
        Task { @MainActor in
            await self.controller.bootstrap(
                completingSetup: completingSetup
            )
            reply(nil)
        }
    }

    func performPermissionAction(
        _ requirement: String,
        reply: @escaping (String?) -> Void
    ) {
        Task { @MainActor in
            guard let requirement = Self.requirement(from: requirement) else {
                reply("未知的权限类型。")
                return
            }
            await self.controller.setup.performAction(for: requirement)
            reply(nil)
        }
    }

    func historyPage(
        _ limit: Int,
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                guard let store = self.controller.captureStore else {
                    throw RuntimeError.persistenceUnavailable
                }
                let context = ModelContext(store.container)
                context.autosaveEnabled = false

                var descriptor = FetchDescriptor<CaptureRecord>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                descriptor.fetchLimit = max(1, min(limit, 500))
                let captures = try context.fetch(descriptor)
                let total = try context.fetchCount(
                    FetchDescriptor<CaptureRecord>()
                )
                let payload = MorieHistoryPageDTO(
                    captures: captures.map { Self.captureDTO($0) },
                    totalCount: total
                )
                reply(try MorieRuntimeCodec.encode(payload), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func historyDetail(
        _ captureID: String,
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let payload = try self.historyDetailDTO(captureID)
                reply(try MorieRuntimeCodec.encode(payload), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func deleteHistory(
        _ captureID: String,
        reply: @escaping (String?) -> Void
    ) {
        Task { @MainActor in
            do {
                guard let store = self.controller.captureStore,
                      let id = UUID(uuidString: captureID)
                else { throw RuntimeError.persistenceUnavailable }
                let history = CaptureHistoryController(
                    store: store,
                    locale: Locale(identifier: "zh-CN")
                )
                try await history.deleteCapture(id)
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    func rerecognizeHistory(
        _ captureID: String,
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                guard let store = self.controller.captureStore,
                      let id = UUID(uuidString: captureID)
                else { throw RuntimeError.persistenceUnavailable }

                let history = CaptureHistoryController(
                    store: store,
                    locale: Locale(identifier: "zh-CN")
                )
                history.setInputActive(self.controller.isCaptureActive)
                history.recognizeAgain(id)
                await history.waitForRecognition()
                let payload = try self.historyDetailDTO(captureID)
                reply(try MorieRuntimeCodec.encode(payload), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func dictionarySnapshot(
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let payload = try self.dictionaryDTOs()
                reply(try MorieRuntimeCodec.encode(payload), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func mutateDictionary(
        _ request: Data,
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                guard let dictionary = self.controller.dictionary else {
                    throw RuntimeError.persistenceUnavailable
                }
                let mutation = try MorieRuntimeCodec.decode(
                    MorieDictionaryMutationDTO.self,
                    from: request
                )
                switch mutation.action {
                case .create:
                    guard let name = mutation.name else {
                        throw RuntimeError.invalidRequest
                    }
                    try dictionary.create(DictionaryDraft(name: name))
                case .update:
                    guard let id = mutation.id,
                          let name = mutation.name else {
                        throw RuntimeError.invalidRequest
                    }
                    try dictionary.update(
                        id,
                        draft: DictionaryDraft(name: name)
                    )
                case .delete:
                    guard let id = mutation.id else {
                        throw RuntimeError.invalidRequest
                    }
                    try dictionary.delete(id)
                }

                reply(
                    try MorieRuntimeCodec.encode(
                        try self.dictionaryDTOs()
                    ),
                    nil
                )
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func memorySnapshot(
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let payload = try self.memoryDTOs()
                reply(try MorieRuntimeCodec.encode(payload), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func mutateMemory(
        _ request: Data,
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                guard let memory = self.controller.memory else {
                    throw RuntimeError.persistenceUnavailable
                }
                let mutation = try MorieRuntimeCodec.decode(
                    MorieMemoryMutationDTO.self,
                    from: request
                )

                func draft() throws -> MemoryDraft {
                    guard let name = mutation.name,
                          let notes = mutation.notes else {
                        throw RuntimeError.invalidRequest
                    }
                    let kind = mutation.kind
                        .flatMap(MemoryKind.init(rawValue:))
                        ?? .fact
                    return MemoryDraft(
                        kind: kind,
                        name: name,
                        notes: notes,
                        scope: .longTerm
                    )
                }

                switch mutation.action {
                case .create:
                    try memory.create(try draft())
                case .update:
                    guard let id = mutation.id else {
                        throw RuntimeError.invalidRequest
                    }
                    try memory.update(id, draft: try draft())
                case .replace:
                    guard let id = mutation.id else {
                        throw RuntimeError.invalidRequest
                    }
                    try memory.replace(id, with: try draft())
                case .archive:
                    guard let id = mutation.id else {
                        throw RuntimeError.invalidRequest
                    }
                    try memory.archive(id)
                case .restore:
                    guard let id = mutation.id else {
                        throw RuntimeError.invalidRequest
                    }
                    try memory.restore(id)
                case .delete:
                    guard let id = mutation.id else {
                        throw RuntimeError.invalidRequest
                    }
                    try memory.delete(id)
                }

                reply(
                    try MorieRuntimeCodec.encode(
                        try self.memoryDTOs()
                    ),
                    nil
                )
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func mutateSettings(
        _ request: Data,
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let mutation = try MorieRuntimeCodec.decode(
                    MorieSettingsMutationDTO.self,
                    from: request
                )
                switch mutation.action {
                case .audioRetentionDays:
                    guard let value = mutation.intValue else {
                        throw RuntimeError.invalidRequest
                    }
                    self.controller.setAudioRetentionDays(value)
                case .inputRefinementEnabled:
                    self.controller.setInputRefinementEnabled(
                        try Self.bool(mutation)
                    )
                case .personalMemoryEnabled:
                    self.controller.setPersonalMemoryEnabled(
                        try Self.bool(mutation)
                    )
                case .correctionSuggestionsEnabled:
                    self.controller.setCorrectionSuggestionsEnabled(
                        try Self.bool(mutation)
                    )
                case .expressionLearningEnabled:
                    self.controller.setExpressionLearningEnabled(
                        try Self.bool(mutation)
                    )
                case .soundFeedbackEnabled:
                    self.controller.setSoundFeedbackEnabled(
                        try Self.bool(mutation)
                    )
                case .captureShortcut:
                    guard let raw = mutation.stringValue,
                          let shortcut = CaptureShortcut(rawValue: raw)
                    else { throw RuntimeError.invalidRequest }
                    self.controller.setCaptureShortcut(shortcut)
                case .iCloudSyncEnabled:
                    self.controller.setICloudSyncEnabled(
                        try Self.bool(mutation)
                    )
                case .refreshICloud:
                    self.controller.refreshICloudSyncState()
                case .refinementMode:
                    guard let raw = mutation.stringValue,
                          let mode = RefinementModelMode(rawValue: raw)
                    else { throw RuntimeError.invalidRequest }
                    self.controller.refinementModels.setMode(mode)
                case .saveCloudConfiguration:
                    guard let baseURL = mutation.baseURL,
                          let modelName = mutation.modelName
                    else { throw RuntimeError.invalidRequest }
                    guard self.controller.refinementModels
                        .saveCloudConfiguration(
                            baseURL: baseURL,
                            modelName: modelName,
                            apiKey: mutation.apiKey ?? ""
                        )
                    else {
                        throw RuntimeError.settingsRejected(
                            self.controller.refinementModels.settingsMessage
                                ?? "API 配置保存失败。"
                        )
                    }
                case .clearCloudAPIKey:
                    guard self.controller.refinementModels.clearCloudAPIKey()
                    else {
                        throw RuntimeError.settingsRejected(
                            self.controller.refinementModels.settingsMessage
                                ?? "无法清除 API Key。"
                        )
                    }
                case .savePrompt:
                    guard let value = mutation.stringValue,
                          self.controller.refinementPrompts.save(value)
                    else {
                        throw RuntimeError.settingsRejected(
                            self.controller.refinementPrompts.settingsMessage
                                ?? "提示词保存失败。"
                        )
                    }
                case .restoreDefaultPrompt:
                    self.controller.refinementPrompts.restoreDefault()
                }

                reply(self.encodedSnapshot(), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func clearExpressionProfile(
        reply: @escaping (Data?, String?) -> Void
    ) {
        Task { @MainActor in
            self.controller.clearExpressionProfile()
            reply(self.encodedSnapshot(), nil)
        }
    }

    func factoryReset(reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.controller.factoryReset()
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func encodedSnapshot() -> Data? {
        try? MorieRuntimeCodec.encode(snapshot())
    }

    @MainActor
    private func snapshot() -> MorieRuntimeSnapshotDTO {
        let phaseAndReason: (String, String?)
        switch controller.runtime.state {
        case .checking: phaseAndReason = ("checking", nil)
        case .blocked(let reason): phaseAndReason = ("blocked", reason)
        case .ready: phaseAndReason = ("ready", nil)
        case .recording: phaseAndReason = ("recording", nil)
        case .stopping: phaseAndReason = ("stopping", nil)
        case .finalizing: phaseAndReason = ("finalizing", nil)
        case .refining: phaseAndReason = ("refining", nil)
        case .delivering: phaseAndReason = ("delivering", nil)
        case .failed(let reason): phaseAndReason = ("failed", reason)
        }

        let checks = controller.setup.checks.map {
            MoriePermissionCheckDTO(
                requirement: Self.requirementRaw($0.requirement),
                state: Self.stateRaw($0.state),
                detail: $0.detail,
                action: $0.action.map(Self.actionRaw)
            )
        }

        let settings = settingsSnapshot()

        let metrics = controller.captureStore
            .flatMap { try? $0.usageMetricsSnapshot() }
            .map {
                MorieUsageMetricsDTO(
                    totalCaptures: $0.totalCaptures,
                    recognizedCharacters: $0.recognizedCharacters,
                    successfulInputs: $0.successfulInputs,
                    currentAppAttempts: $0.currentAppAttempts,
                    failedInputs: $0.failedInputs,
                    refinementSamples: $0.refinementSamples,
                    refinementDurationTotal: $0.refinementDurationTotal
                )
            }

        return MorieRuntimeSnapshotDTO(
            phase: phaseAndReason.0,
            reason: phaseAndReason.1,
            transcript: controller.runtime.transcript,
            canStartCapture: controller.canStartCapture,
            isCaptureActive: controller.isCaptureActive,
            canCompleteSetup: controller.canCompleteSetup,
            isBootstrapping: controller.capabilities.isBootstrapping,
            setupError: controller.capabilities.setupError,
            speechBackendName: controller.capabilities.speechBackend?.displayName,
            speechLocaleIdentifier:
                controller.capabilities.speechBackend?.localeIdentifier,
            speechIsFallback:
                controller.capabilities.speechBackend?.isFallback ?? false,
            permissionChecks: checks,
            settings: settings,
            usageMetrics: metrics
        )
    }

    @MainActor
    private func settingsSnapshot() -> MorieSettingsSnapshotDTO {
        let preferences = controller.preferences
        let model = controller.refinementModels

        let iCloudKind: String
        switch preferences.iCloudSyncState {
        case .off: iCloudKind = "off"
        case .checking: iCloudKind = "checking"
        case .ready: iCloudKind = "ready"
        case .restartRequired: iCloudKind = "restartRequired"
        case .unavailable: iCloudKind = "unavailable"
        }

        return MorieSettingsSnapshotDTO(
            captureShortcut: preferences.captureShortcut.rawValue,
            audioRetentionDays: preferences.audioRetentionDays,
            inputRefinementEnabled: preferences.inputRefinementEnabled,
            personalMemoryEnabled: preferences.personalMemoryEnabled,
            correctionSuggestionsEnabled:
                preferences.correctionSuggestionsEnabled,
            expressionLearningEnabled:
                preferences.expressionLearningEnabled,
            soundFeedbackEnabled: preferences.soundFeedbackEnabled,
            iCloudSyncEnabled: preferences.iCloudSyncEnabled,
            iCloudStateKind: iCloudKind,
            iCloudStateDetail: preferences.iCloudSyncState.detail,
            refinementMode: model.mode.rawValue,
            refinementModelName: model.modelName,
            refinementModelDetail: model.modelDetail,
            refinementModelStatus: model.modelStatusTitle(
                inputRefinementEnabled:
                    preferences.inputRefinementEnabled
            ),
            cloudBaseURL: model.cloudBaseURL,
            cloudModelName: model.cloudModelName,
            cloudConfigurationStatus: model.configurationStatusTitle,
            refinementInstructions:
                controller.refinementPrompts.instructions,
            refinementPromptIsDefault:
                controller.refinementPrompts.isDefault
        )
    }

    @MainActor
    private func historyDetailDTO(
        _ captureID: String
    ) throws -> MorieCaptureDTO {
        guard let store = controller.captureStore,
              let id = UUID(uuidString: captureID)
        else { throw RuntimeError.invalidRequest }

        let context = ModelContext(store.container)
        context.autosaveEnabled = false
        guard let capture = try context.fetch(
            FetchDescriptor<CaptureRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first else {
            throw RuntimeError.captureUnavailable
        }

        var dto = Self.captureDTO(capture)
        let audioURL = try? store.sourceAudioURL(for: id)
        dto = MorieCaptureDTO(
            id: dto.id,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            lifecycle: dto.lifecycle,
            deliveryMode: dto.deliveryMode,
            recognizedText: dto.recognizedText,
            finalText: dto.finalText,
            sourceApplicationName: dto.sourceApplicationName,
            sourceBundleIdentifier: dto.sourceBundleIdentifier,
            deliveryErrorDescription: dto.deliveryErrorDescription,
            sourceAudioURL: audioURL,
            sourceAudioDurationSeconds: dto.sourceAudioDurationSeconds,
            sourceAudioExpiresAt: dto.sourceAudioExpiresAt,
            lastRecognitionAttemptAt: dto.lastRecognitionAttemptAt,
            lastRecognitionErrorDescription:
                dto.lastRecognitionErrorDescription,
            refinement: dto.refinement
        )
        return dto
    }

    @MainActor
    private func dictionaryDTOs() throws -> [MorieDictionaryEntryDTO] {
        guard let dictionary = controller.dictionary else {
            throw RuntimeError.persistenceUnavailable
        }
        try dictionary.load()
        return dictionary.displayEntries.map {
            MorieDictionaryEntryDTO(
                id: $0.id,
                name: $0.name,
                source: $0.source.rawValue
            )
        }
    }

    @MainActor
    private func memoryDTOs() throws -> [MorieMemoryDTO] {
        guard let memory = controller.memory else {
            throw RuntimeError.persistenceUnavailable
        }
        try memory.load()
        return memory.entries.compactMap { record in
            guard let kind = record.kind,
                  let scope = record.scope,
                  let status = record.status,
                  let origin = record.origin else {
                return nil
            }
            return MorieMemoryDTO(
                id: record.id,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                kind: kind.rawValue,
                scope: scope.rawValue,
                status: status.rawValue,
                archiveReason: record.archiveReason?.rawValue,
                name: record.name,
                notes: record.notes,
                sourceCaptureIDs: record.sourceCaptureIDs,
                origin: origin.rawValue,
                lastEvidenceAt: record.lastEvidenceAt,
                confidence: record.confidence,
                expiresAt: record.expiresAt,
                supersedesID: record.supersedesID,
                evidence: memory.evidence(for: record.id).map {
                    MorieMemoryEvidenceDTO(
                        id: $0.id,
                        sourceCaptureID: $0.sourceCaptureID,
                        sourceText: $0.sourceText,
                        claim: $0.claim,
                        capturedAt: $0.capturedAt,
                        confidence: $0.confidence
                    )
                }
            )
        }
    }

    private static func captureDTO(
        _ capture: CaptureRecord
    ) -> MorieCaptureDTO {
        let refinement = capture.refinement.map {
            MorieCaptureRefinementDTO(
                status: $0.status.rawValue,
                reason: $0.reason?.rawValue,
                reasonMessage: $0.reason?.message,
                durationSeconds: $0.durationSeconds
            )
        }
        return MorieCaptureDTO(
            id: capture.id,
            createdAt: capture.createdAt,
            updatedAt: capture.updatedAt,
            lifecycle: capture.lifecycleRawValue,
            deliveryMode: capture.deliveryModeRawValue,
            recognizedText: capture.recognizedText,
            finalText: capture.finalText,
            sourceApplicationName: capture.sourceApplicationName,
            sourceBundleIdentifier: capture.sourceBundleIdentifier,
            deliveryErrorDescription:
                capture.deliveryErrorDescription,
            sourceAudioURL: nil,
            sourceAudioDurationSeconds:
                capture.sourceAudioDurationSeconds,
            sourceAudioExpiresAt: capture.sourceAudioExpiresAt,
            lastRecognitionAttemptAt:
                capture.lastRecognitionAttemptAt,
            lastRecognitionErrorDescription:
                capture.lastRecognitionErrorDescription,
            refinement: refinement
        )
    }

    private static func bool(
        _ mutation: MorieSettingsMutationDTO
    ) throws -> Bool {
        guard let value = mutation.boolValue else {
            throw RuntimeError.invalidRequest
        }
        return value
    }

    private static func requirementRaw(
        _ requirement: SetupRequirement
    ) -> String {
        switch requirement {
        case .appleIntelligence: "appleIntelligence"
        case .speechTranscription: "speechTranscription"
        case .microphone: "microphone"
        case .speechRecognition: "speechRecognition"
        case .accessibility: "accessibility"
        }
    }

    private static func requirement(
        from raw: String
    ) -> SetupRequirement? {
        switch raw {
        case "appleIntelligence": .appleIntelligence
        case "speechTranscription": .speechTranscription
        case "microphone": .microphone
        case "speechRecognition": .speechRecognition
        case "accessibility": .accessibility
        default: nil
        }
    }

    private static func stateRaw(
        _ state: CapabilityCheck.State
    ) -> String {
        switch state {
        case .ready: "ready"
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .unavailable: "unavailable"
        }
    }

    private static func actionRaw(
        _ action: CapabilityCheck.Action
    ) -> String {
        switch action {
        case .requestPermission: "requestPermission"
        case .openSettings: "openSettings"
        }
    }

    private enum RuntimeError: LocalizedError {
        case persistenceUnavailable
        case invalidRequest
        case captureUnavailable
        case settingsRejected(String)

        var errorDescription: String? {
            switch self {
            case .persistenceUnavailable:
                "Morie Runtime 的本地存储不可用。"
            case .invalidRequest:
                "Morie Runtime 收到了无效请求。"
            case .captureUnavailable:
                "此历史记录已不存在。"
            case .settingsRejected(let message):
                message
            }
        }
    }
}
