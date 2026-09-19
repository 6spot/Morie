import Foundation
import SwiftData

enum MemoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum MemoryStatus: String, Codable, CaseIterable, Identifiable, Sendable {
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

struct MemoryDraft: Codable, Equatable, Sendable {
    var kind: MemoryKind = .fact
    var name = ""
    var notes = ""
}

enum MemoryOrigin: String, Codable, Sendable {
    case automatic, user
    var title: String { self == .automatic ? "从日常输入中自动学习" : "由你手动编辑" }
}

@Model
final class MemoryRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var kindRawValue: String = MemoryKind.fact.rawValue
    var statusRawValue: String = MemoryStatus.active.rawValue
    var name: String = ""
    var notes: String = ""
    var sourceCaptureIDs: [UUID] = []
    var originRawValue: String = MemoryOrigin.user.rawValue
    var lastEvidenceAt: Date = Date()
    var confidence: Double?
    var supersedesID: UUID?

    init(draft: MemoryDraft, sourceCaptureIDs: [UUID] = [], supersedesID: UUID? = nil) {
        kindRawValue = draft.kind.rawValue
        name = draft.name
        notes = draft.notes
        self.sourceCaptureIDs = sourceCaptureIDs
        self.supersedesID = supersedesID
    }

    var kind: MemoryKind? { MemoryKind(rawValue: kindRawValue) }
    var status: MemoryStatus? { MemoryStatus(rawValue: statusRawValue) }
    var origin: MemoryOrigin? { MemoryOrigin(rawValue: originRawValue) }

    var draft: MemoryDraft? {
        guard let kind else { return nil }
        return MemoryDraft(kind: kind, name: name, notes: notes)
    }

    var snapshot: MemorySnapshot? {
        guard let kind, let status, let origin else { return nil }
        return MemorySnapshot(
            id: id, kind: kind, status: status, name: name,
            notes: notes, origin: origin, updatedAt: updatedAt
        )
    }
}

struct MemorySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MemoryKind
    let status: MemoryStatus
    let name: String
    let notes: String
    let origin: MemoryOrigin
    let updatedAt: Date
}

enum MemoryText {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
