import Foundation

enum MorieRuntimeIPC {
    static let serviceName = "me.morie.mac.runtime"
    static let launchAgentPlistName = "me.morie.mac.runtime.plist"
}

@objc protocol MorieRuntimeXPCProtocol {
    func runtimeSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void)
    func startCaptureOnly(reply: @escaping @Sendable (String?) -> Void)
    func bootstrap(_ completingSetup: Bool, reply: @escaping @Sendable (String?) -> Void)
    func performPermissionAction(_ requirement: String, reply: @escaping @Sendable (String?) -> Void)

    func historyPage(_ limit: Int, reply: @escaping @Sendable (Data?, String?) -> Void)
    func historyDetail(_ captureID: String, reply: @escaping @Sendable (Data?, String?) -> Void)
    func deleteHistory(_ captureID: String, reply: @escaping @Sendable (String?) -> Void)
    func rerecognizeHistory(_ captureID: String, reply: @escaping @Sendable (Data?, String?) -> Void)
    func cancelRerecognition(_ captureID: String, reply: @escaping @Sendable (String?) -> Void)

    func dictionarySnapshot(reply: @escaping @Sendable (Data?, String?) -> Void)
    func mutateDictionary(_ request: Data, reply: @escaping @Sendable (Data?, String?) -> Void)

    func memorySnapshot(reply: @escaping @Sendable (Data?, String?) -> Void)
    func mutateMemory(_ request: Data, reply: @escaping @Sendable (Data?, String?) -> Void)

    func mutateSettings(_ request: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func clearExpressionProfile(reply: @escaping @Sendable (Data?, String?) -> Void)
    func factoryReset(reply: @escaping @Sendable (String?) -> Void)
}

enum MorieRuntimeCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

enum MorieCaptureLifecycleDTO: String, Codable, Equatable, Sendable {
    case capturing
    case recognized
    case delivered
    case deliveryFailed
    case cancelled
    case failed
}

enum MorieCaptureDeliveryModeDTO: String, Codable, Equatable, Sendable {
    case currentApp
    case captureOnly
}

enum MorieRefinementStatusDTO: String, Codable, Equatable, Sendable {
    case running
    case applied
    case unchanged
    case skipped
    case timedOut
    case failed
    case interrupted

    var title: String {
        switch self {
        case .running: "正在润色…"
        case .applied: "已润色"
        case .unchanged: "无需修改"
        case .skipped: "已跳过"
        case .timedOut: "润色超时"
        case .failed: "已保留原文字"
        case .interrupted: "已中断"
        }
    }
}

enum MorieRefinementReasonDTO: String, Codable, Equatable, Sendable {
    case disabled
    case modelBusy
    case unavailable
    case unsupportedLanguage
    case textTooLong
    case declined
    case generationFailed
    case invalidEdits
    case memoryChanged
    case dictionaryChanged
    case expressionStyleChanged
    case timeLimit
    case interrupted
    case saveFailed

    var message: String {
        switch self {
        case .disabled: "AI 润色已关闭，自定义字典仍然生效。"
        case .modelBusy: "前一次本机分析尚未结束，本次使用字典修正后的文字继续输入。"
        case .unavailable: "Apple 智能暂不可用，本次使用字典修正后的文字继续输入。"
        case .unsupportedLanguage: "本机模型暂不支持润色这种语言，已保留保存的文字。"
        case .textTooLong: "输入内容超过单次本机处理范围，已保留完整文字。"
        case .declined: "Apple 智能未能处理本次润色，已保留保存的文字。"
        case .generationFailed: "AI 润色未能完成，已保留保存的文字。"
        case .invalidEdits: "AI 润色返回了不可用的文本，已使用字典修正后的文字继续输入。"
        case .memoryChanged: "润色期间个人记忆发生变化，已使用字典修正后的文字继续输入。"
        case .dictionaryChanged: "润色期间字典发生变化，已保留识别文字。"
        case .expressionStyleChanged: "润色期间表达习惯发生变化，已使用当前保存的文字继续输入。"
        case .timeLimit: "AI 润色超时，已使用字典修正后的文字继续输入。"
        case .interrupted: "输入处理已中断，已保存的文字和录音均已保留。"
        case .saveFailed: "无法保存处理结果，已保留此前保存的文字。"
        }
    }
}

enum MorieDictionaryEntrySourceDTO: String, Codable, Equatable, Sendable {
    case builtIn
    case manual
    case correction

    var helpText: String {
        switch self {
        case .builtIn: "Morie 内置词语"
        case .manual: "手动添加"
        case .correction: "纠错确认添加"
        }
    }
}

enum MorieMemoryKindDTO: String, Codable, CaseIterable, Identifiable, Sendable {
    case project
    case person
    case preference
    case fact
    case decision

    var id: Self { self }

    var title: String {
        switch self {
        case .project: "项目"
        case .person: "人物"
        case .preference: "偏好"
        case .fact: "个人信息"
        case .decision: "决定"
        }
    }

    var systemImage: String {
        switch self {
        case .project: "folder"
        case .person: "person"
        case .preference: "slider.horizontal.3"
        case .fact: "person.text.rectangle"
        case .decision: "checkmark.circle"
        }
    }
}

enum MorieMemoryScopeDTO: String, Codable, Equatable, Sendable {
    case longTerm
    case workingContext
}

enum MorieMemoryStatusDTO: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case archived
    case superseded

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "使用中"
        case .archived: "已归档"
        case .superseded: "已替代"
        }
    }
}

enum MorieMemoryArchiveReasonDTO: String, Codable, Equatable, Sendable {
    case user
    case expired
}

enum MorieMemoryOriginDTO: String, Codable, Equatable, Sendable {
    case automatic
    case user

    var title: String {
        self == .automatic ? "从日常输入中自动学习" : "由你手动编辑"
    }
}

struct MorieMemoryDraftDTO: Codable, Equatable, Sendable {
    var kind: MorieMemoryKindDTO = .fact
    var name = ""
    var notes = ""
    var scope: MorieMemoryScopeDTO = .longTerm
}

struct MoriePermissionCheckDTO: Codable, Equatable, Identifiable, Sendable {
    let requirement: String
    let state: String
    let detail: String?
    let action: String?

    var id: String { requirement }
}

struct MorieUsageMetricsDTO: Codable, Equatable, Sendable {
    let totalCaptures: Int
    let recognizedCharacters: Int
    let successfulInputs: Int
    let currentAppAttempts: Int
    let failedInputs: Int
    let refinementSamples: Int
    let refinementDurationTotal: Double

    var averageRefinementSeconds: Double? {
        guard refinementSamples > 0 else { return nil }
        return refinementDurationTotal / Double(refinementSamples)
    }

    var failureRate: Double? {
        guard currentAppAttempts > 0 else { return nil }
        return Double(failedInputs) / Double(currentAppAttempts)
    }
}

struct MorieSettingsSnapshotDTO: Codable, Equatable, Sendable {
    let captureShortcut: String
    let audioRetentionDays: Int
    let inputRefinementEnabled: Bool
    let personalMemoryEnabled: Bool
    let correctionSuggestionsEnabled: Bool
    let expressionLearningEnabled: Bool
    let soundFeedbackEnabled: Bool
    let iCloudSyncEnabled: Bool
    let iCloudStateKind: String
    let iCloudStateDetail: String

    let refinementMode: String
    let refinementModelName: String
    let refinementModelDetail: String
    let refinementModelStatus: String
    let cloudBaseURL: String
    let cloudModelName: String
    let cloudConfigurationStatus: String

    let refinementInstructions: String
    let refinementPromptIsDefault: Bool
}

struct MorieRuntimeSnapshotDTO: Codable, Equatable, Sendable {
    let phase: String
    let reason: String?
    let transcript: String
    let canStartCapture: Bool
    let isCaptureActive: Bool
    let canCompleteSetup: Bool
    let isBootstrapping: Bool
    let setupError: String?
    let speechBackendName: String?
    let speechLocaleIdentifier: String?
    let speechIsFallback: Bool
    let permissionChecks: [MoriePermissionCheckDTO]
    let settings: MorieSettingsSnapshotDTO
    let usageMetrics: MorieUsageMetricsDTO?
}

struct MorieCaptureRefinementDTO: Codable, Equatable, Sendable {
    let status: MorieRefinementStatusDTO
    let reason: MorieRefinementReasonDTO?
    let reasonMessage: String?
    let durationSeconds: Double?
}

struct MorieCaptureDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let lifecycle: MorieCaptureLifecycleDTO
    let deliveryMode: MorieCaptureDeliveryModeDTO
    let recognizedText: String
    let finalText: String
    let sourceApplicationName: String?
    let sourceBundleIdentifier: String?
    let deliveryErrorDescription: String?
    let sourceAudioURL: URL?
    let sourceAudioDurationSeconds: Double?
    let sourceAudioExpiresAt: Date?
    let lastRecognitionAttemptAt: Date?
    let lastRecognitionErrorDescription: String?
    let refinement: MorieCaptureRefinementDTO?

    var deliveryModeRawValue: String { deliveryMode.rawValue }
}

struct MorieHistoryPageDTO: Codable, Equatable, Sendable {
    let captures: [MorieCaptureDTO]
    let totalCount: Int
}

struct MorieDictionaryEntryDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let source: MorieDictionaryEntrySourceDTO

    var isEditable: Bool { source != .builtIn }
}

struct MorieDictionaryMutationDTO: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    let action: Action
    var id: UUID? = nil
    var name: String? = nil
}

struct MorieMemoryEvidenceDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceCaptureID: UUID
    let sourceText: String
    let claim: String
    let capturedAt: Date
    let confidence: Double?
}

struct MorieMemoryDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let kind: MorieMemoryKindDTO?
    let scope: MorieMemoryScopeDTO?
    let status: MorieMemoryStatusDTO?
    let archiveReason: MorieMemoryArchiveReasonDTO?
    let name: String
    let notes: String
    let sourceCaptureIDs: [UUID]
    let origin: MorieMemoryOriginDTO?
    let lastEvidenceAt: Date
    let confidence: Double?
    let expiresAt: Date?
    let supersedesID: UUID?
    let evidence: [MorieMemoryEvidenceDTO]

    var draft: MorieMemoryDraftDTO? {
        guard let kind, let scope else { return nil }
        return MorieMemoryDraftDTO(
            kind: kind,
            name: name,
            notes: notes,
            scope: scope
        )
    }
}

struct MorieMemoryMutationDTO: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case create
        case update
        case replace
        case archive
        case restore
        case delete
    }

    let action: Action
    var id: UUID? = nil
    var kind: MorieMemoryKindDTO? = nil
    var name: String? = nil
    var notes: String? = nil
}

struct MorieSettingsMutationDTO: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case audioRetentionDays
        case inputRefinementEnabled
        case personalMemoryEnabled
        case correctionSuggestionsEnabled
        case expressionLearningEnabled
        case soundFeedbackEnabled
        case captureShortcut
        case iCloudSyncEnabled
        case refreshICloud
        case refinementMode
        case saveCloudConfiguration
        case clearCloudAPIKey
        case savePrompt
        case restoreDefaultPrompt
    }

    let action: Action
    var boolValue: Bool? = nil
    var intValue: Int? = nil
    var stringValue: String? = nil
    var baseURL: String? = nil
    var modelName: String? = nil
    var apiKey: String? = nil
}
