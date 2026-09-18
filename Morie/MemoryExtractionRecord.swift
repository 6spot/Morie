import Foundation
import SwiftData

enum MemoryInputTextKind: String, Codable, Sendable {
    case finalText
    case recognizedText

    var title: String { self == .finalText ? "Saved final text" : "Saved recognized text" }
}

struct MemoryExtractionInput: Equatable, Sendable {
    let captureID: UUID
    let text: String
    let textKind: MemoryInputTextKind

    init(capture: CaptureRecord) {
        captureID = capture.id
        if !capture.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = capture.finalText
            textKind = .finalText
        } else {
            text = capture.recognizedText
            textKind = .recognizedText
        }
    }

    init(captureID: UUID, text: String, textKind: MemoryInputTextKind) {
        self.captureID = captureID
        self.text = text
        self.textKind = textKind
    }
}

struct MemorySuggestion: Codable, Equatable, Sendable {
    var draft: MemoryDraft
    let evidence: String
    // The model's estimate is a selection signal, not a calibrated probability.
    let confidence: Double
}

enum MemoryCandidateStatus: String, Codable, Sendable {
    case pending
    case accepted
    case dismissed
}

struct MemoryCandidate: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let suggestion: MemorySuggestion
    var status: MemoryCandidateStatus = .pending
    var memoryID: UUID?
}

@Model
final class MemoryExtractionRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var sourceCaptureID: UUID = UUID()
    var sourceText: String = ""
    var sourceTextKindRawValue: String = MemoryInputTextKind.finalText.rawValue
    var candidates: [MemoryCandidate] = []

    init(input: MemoryExtractionInput, suggestions: [MemorySuggestion]) {
        sourceCaptureID = input.captureID
        sourceText = input.text
        sourceTextKindRawValue = input.textKind.rawValue
        candidates = suggestions.map { MemoryCandidate(suggestion: $0) }
    }

    var input: MemoryExtractionInput? {
        guard let kind = MemoryInputTextKind(rawValue: sourceTextKindRawValue) else { return nil }
        return MemoryExtractionInput(captureID: sourceCaptureID, text: sourceText, textKind: kind)
    }
}
