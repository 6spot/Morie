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
        case .unavailable: "Apple Intelligence is unavailable. Memory learning will retry automatically."
        case .unsupportedLanguage: "The on-device model could not analyze this language. Your input is saved."
        case .textTooLong: "This input is too long for one on-device analysis. Its full text is saved."
        case .declined: "Apple Intelligence could not analyze this input. Your input is saved."
        case .generationFailed: "Memory learning could not finish. It will retry automatically."
        case .sourceChanged: "The saved input changed. The previous analysis was not used."
        }
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
