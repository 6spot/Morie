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

struct MemoryBlockedSnapshot: Codable, Equatable, Sendable {
    let kind: MemoryKind
    let name: String
    let notes: String
}

struct MemoryLearningInput: Codable, Equatable, Sendable {
    let source: MemoryAnalysisSource
    let context: [MemorySnapshot]
    let blocked: [MemoryBlockedSnapshot]
}

enum MemoryLearningAction: String, Codable, Sendable {
    case create
    case merge
    case update
    case reinforce
}

struct MemorySuggestion: Codable, Equatable, Sendable {
    var draft: MemoryDraft
    let evidence: String
    let confidence: Double
    var action: MemoryLearningAction = .create
    var existingMemoryID: UUID?
}

enum MemoryObservationDisposition: String, Codable, Sendable {
    case learned
    case ignored
    case conflict
}

struct MemoryObservation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let suggestion: MemorySuggestion
    var disposition: MemoryObservationDisposition = .ignored
    var memoryID: UUID?
}

enum MemoryAnalysisState: String, Codable, Sendable {
    case pending
    case completed
    case skipped
}

enum MemoryAnalysisFailure: String, Codable, Error, Sendable {
    case unavailable
    case unsupportedLanguage
    case textTooLong
    case declined
    case generationFailed
    case sourceChanged
    case disabled

    var retryable: Bool {
        self == .unavailable || self == .generationFailed
    }

    var message: String {
        switch self {
        case .unavailable:
            "Apple 智能暂不可用，个人记忆学习会自动重试。"
        case .unsupportedLanguage:
            "本机模型暂不支持分析这种语言，你的输入已保存。"
        case .textTooLong:
            "输入内容超过单次本机分析范围，完整文字已保存。"
        case .declined:
            "Apple 智能未能分析这次输入，你的输入已保存。"
        case .generationFailed:
            "个人记忆学习未能完成，稍后会自动重试。"
        case .sourceChanged:
            "保存的输入已发生变化，此前的分析结果未被使用。"
        case .disabled:
            "个人记忆已关闭，这次输入未参与学习。"
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

    var source: MemoryAnalysisSource {
        MemoryAnalysisSource(
            captureID: sourceCaptureID,
            text: sourceText,
            capturedAt: sourceCapturedAt
        )
    }

    var state: MemoryAnalysisState? {
        MemoryAnalysisState(rawValue: stateRawValue)
    }

    var failure: MemoryAnalysisFailure? {
        failureRawValue.flatMap(MemoryAnalysisFailure.init(rawValue:))
    }
}

/// A semantic tombstone retained after the user deletes a topic.
/// It is supplied to the writer model as context so deletion is respected
/// without pretending a generated title string is the topic's identity.
@Model
final class MemoryLearningBlock {
    var id: UUID = UUID()
    var kindRawValue: String = MemoryKind.fact.rawValue
    var name: String = ""
    var notes: String = ""

    init(draft: MemoryDraft) {
        kindRawValue = draft.kind.rawValue
        name = draft.name
        notes = draft.notes
    }

    var snapshot: MemoryBlockedSnapshot? {
        guard let kind = MemoryKind(rawValue: kindRawValue) else { return nil }
        return MemoryBlockedSnapshot(kind: kind, name: name, notes: notes)
    }
}
