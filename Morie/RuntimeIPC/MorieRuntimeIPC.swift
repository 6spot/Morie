import Foundation

enum MorieRuntimeIPC {
    static let serviceName = "me.morie.mac.runtime"
    static let launchAgentPlistName = "me.morie.mac.runtime.plist"
}

@objc protocol MorieRuntimeXPCProtocol {
    func runtimeSnapshot(reply: @escaping (Data?, String?) -> Void)
    func startCaptureOnly(reply: @escaping (String?) -> Void)
    func bootstrap(_ completingSetup: Bool, reply: @escaping (String?) -> Void)
    func performPermissionAction(_ requirement: String, reply: @escaping (String?) -> Void)

    func historyPage(_ limit: Int, reply: @escaping (Data?, String?) -> Void)
    func historyDetail(_ captureID: String, reply: @escaping (Data?, String?) -> Void)
    func deleteHistory(_ captureID: String, reply: @escaping (String?) -> Void)
    func rerecognizeHistory(_ captureID: String, reply: @escaping (Data?, String?) -> Void)

    func dictionarySnapshot(reply: @escaping (Data?, String?) -> Void)
    func mutateDictionary(_ request: Data, reply: @escaping (Data?, String?) -> Void)

    func memorySnapshot(reply: @escaping (Data?, String?) -> Void)
    func mutateMemory(_ request: Data, reply: @escaping (Data?, String?) -> Void)

    func mutateSettings(_ request: Data, reply: @escaping (Data?, String?) -> Void)
    func clearExpressionProfile(reply: @escaping (Data?, String?) -> Void)
    func factoryReset(reply: @escaping (String?) -> Void)
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
    let status: String
    let reason: String?
    let reasonMessage: String?
    let durationSeconds: Double?
}

struct MorieCaptureDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let lifecycle: String
    let deliveryMode: String
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
}

struct MorieHistoryPageDTO: Codable, Equatable, Sendable {
    let captures: [MorieCaptureDTO]
    let totalCount: Int
}

struct MorieDictionaryEntryDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let source: String

    var isEditable: Bool { source != "builtIn" }
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
    let kind: String
    let scope: String
    let status: String
    let archiveReason: String?
    let name: String
    let notes: String
    let sourceCaptureIDs: [UUID]
    let origin: MemoryOrigin?
    let lastEvidenceAt: Date
    let confidence: Double?
    let expiresAt: Date?
    let supersedesID: UUID?
    let evidence: [MorieMemoryEvidenceDTO]
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
    var kind: String? = nil
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


extension MorieCaptureDTO {
    var deliveryModeRawValue: String { deliveryMode.rawValue }
}

extension MorieMemoryDTO {
    var draft: MemoryDraft? {
        guard let kind, let scope else { return nil }
        return MemoryDraft(
            kind: kind,
            name: name,
            notes: notes,
            scope: scope
        )
    }
}
