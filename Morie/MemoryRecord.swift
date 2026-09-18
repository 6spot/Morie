import Foundation
import SwiftData

enum MemoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vocabulary
    case project

    var id: Self { self }
    var title: String { self == .vocabulary ? "Vocabulary" : "Project" }
    var systemImage: String { self == .vocabulary ? "text.book.closed" : "folder" }
}

enum MemoryStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case archived
    case superseded

    var id: Self { self }
    var title: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .superseded: "Superseded"
        }
    }
}

struct MemoryDraft: Codable, Equatable, Sendable {
    var kind: MemoryKind = .vocabulary
    var name = ""
    var aliases: [String] = []
    var notes = ""
}

@Model
final class MemoryRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var kindRawValue: String = MemoryKind.vocabulary.rawValue
    var statusRawValue: String = MemoryStatus.active.rawValue
    var name: String = ""
    var aliases: [String] = []
    var notes: String = ""
    var sourceCaptureIDs: [UUID] = []
    var userConfirmed: Bool = false
    // Manual confirmation is not an inferred model confidence score.
    var confidence: Double?
    var sourceCandidateID: UUID?
    var supersedesID: UUID?

    init(draft: MemoryDraft, sourceCaptureIDs: [UUID] = [], supersedesID: UUID? = nil) {
        kindRawValue = draft.kind.rawValue
        name = draft.name
        aliases = draft.aliases
        notes = draft.notes
        self.sourceCaptureIDs = sourceCaptureIDs
        self.supersedesID = supersedesID
        userConfirmed = true
    }

    var kind: MemoryKind? { MemoryKind(rawValue: kindRawValue) }
    var status: MemoryStatus? { MemoryStatus(rawValue: statusRawValue) }

    var draft: MemoryDraft? {
        guard let kind else { return nil }
        return MemoryDraft(kind: kind, name: name, aliases: aliases, notes: notes)
    }

    var snapshot: MemorySnapshot? {
        guard let kind, let status else { return nil }
        return MemorySnapshot(
            id: id, kind: kind, status: status, name: name, aliases: aliases,
            notes: notes, userConfirmed: userConfirmed, updatedAt: updatedAt
        )
    }
}

struct MemorySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MemoryKind
    let status: MemoryStatus
    let name: String
    let aliases: [String]
    let notes: String
    let userConfirmed: Bool
    let updatedAt: Date
}

enum MemoryText {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
