import CryptoKit
import Foundation
import SwiftData

struct MemoryAnalysisSource: Codable, Equatable, Sendable {
    let captureID: UUID
    let text: String
    let capturedAt: Date

    init(capture: CaptureRecord) {
        captureID = capture.id
        text = capture.finalText
        capturedAt = capture.createdAt
    }

    init(captureID: UUID, text: String, capturedAt: Date) {
        self.captureID = captureID
        self.text = text
        self.capturedAt = capturedAt
    }
}

struct MemoryLearningInput: Codable, Equatable, Sendable {
    let source: MemoryAnalysisSource
    let context: [MemorySnapshot]
}

enum MemoryEvidenceKind: String, Codable, Sendable {
    case explicitPersonal, recurringPersonal, temporary, uncertain, quoted
}

enum MemoryLearningAction: String, Codable, Sendable { case remember, update }

struct MemorySuggestion: Codable, Equatable, Sendable {
    var draft: MemoryDraft
    let evidence: String
    let confidence: Double
    var evidenceKind: MemoryEvidenceKind = .explicitPersonal
    var action: MemoryLearningAction = .remember
    var existingMemoryID: UUID?
}

enum MemoryObservationDisposition: String, Codable, Sendable {
    case accumulating, learned, ignored, conflict
}

struct MemoryObservation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let suggestion: MemorySuggestion
    var disposition: MemoryObservationDisposition = .accumulating
    var memoryID: UUID?
}

enum MemoryAnalysisState: String, Codable, Sendable { case pending, completed, skipped }

enum MemoryAnalysisFailure: String, Codable, Error, Sendable {
    case unavailable, unsupportedLanguage, textTooLong, declined, generationFailed, sourceChanged

    var retryable: Bool { self == .unavailable || self == .generationFailed }
    var message: String {
        switch self {
        case .unavailable: "Apple 智能暂不可用，个人记忆学习会自动重试。"
        case .unsupportedLanguage: "本机模型暂不支持分析这种语言，你的输入已保存。"
        case .textTooLong: "输入内容超过单次本机分析范围，完整文字已保存。"
        case .declined: "Apple 智能未能分析这次输入，你的输入已保存。"
        case .generationFailed: "个人记忆学习未能完成，稍后会自动重试。"
        case .sourceChanged: "保存的输入已发生变化，此前的分析结果未被使用。"
        }
    }
}

struct MemoryAnalysisSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: MemoryAnalysisSource
    let state: MemoryAnalysisState?
    let failure: MemoryAnalysisFailure?
    let observations: [MemoryObservation]

    var sourceCaptureID: UUID { source.captureID }
    var sourceText: String { source.text }

    init(_ record: MemoryAnalysisRecord) {
        id = record.id
        source = record.source
        state = record.state
        failure = record.failure
        observations = record.observations
    }
}

@Model
final class MemoryAnalysisRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var sourceCaptureID: UUID = UUID()
    var sourceText: String = ""
    var sourceCapturedAt: Date = Date()
    var stateRawValue: String = MemoryAnalysisState.pending.rawValue
    var attempts: Int = 0
    var nextAttemptAt: Date = Date()
    var failureRawValue: String?
    var contextSnapshot: [MemorySnapshot] = []
    var observations: [MemoryObservation] = []

    init(source: MemoryAnalysisSource) {
        sourceCaptureID = source.captureID
        sourceText = source.text
        sourceCapturedAt = source.capturedAt
    }

    var source: MemoryAnalysisSource { MemoryAnalysisSource(captureID: sourceCaptureID, text: sourceText, capturedAt: sourceCapturedAt) }
    var state: MemoryAnalysisState? { MemoryAnalysisState(rawValue: stateRawValue) }
    var failure: MemoryAnalysisFailure? { failureRawValue.flatMap(MemoryAnalysisFailure.init(rawValue:)) }
}

/// Retain only a hash of the semantic key so deleting a memory cannot immediately relearn it.
/// Explicit manual creation removes the corresponding block. This is a current user action, not a migration.
@Model
final class MemoryLearningBlock {
    var id: UUID = UUID()
    var keyHash: String = ""

    init(draft: MemoryDraft) { keyHash = Self.key(for: draft) }

    static func key(for draft: MemoryDraft) -> String {
        let key = draft.kind.rawValue + ":" + MemoryText.normalized(draft.name)
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
