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

enum MemoryScope: String, Codable, Sendable {
    case longTerm
    case workingContext
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

enum MemoryArchiveReason: String, Codable, Sendable {
    case user
    case expired
}

struct MemoryDraft: Codable, Equatable, Sendable {
    var kind: MemoryKind = .fact
    var name = ""
    var notes = ""
    var scope: MemoryScope = .longTerm
}

enum MemoryOrigin: String, Codable, Sendable {
    case automatic
    case user

    var title: String {
        self == .automatic ? "从日常输入中自动学习" : "由你手动编辑"
    }
}

enum PersonalMemorySettings {
    static let enabledDefaultsKey = "personalMemoryEnabled"

    static var isEnabled: Bool {
        MorieDefaults.shared.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        MorieDefaults.shared.set(enabled, forKey: enabledDefaultsKey)
    }
}

@Model
final class MemoryRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var kindRawValue: String = MemoryKind.fact.rawValue
    var scopeRawValue: String = MemoryScope.longTerm.rawValue
    var statusRawValue: String = MemoryStatus.active.rawValue
    var archiveReasonRawValue: String?
    var name: String = ""
    var notes: String = ""
    var sourceCaptureIDs: [UUID] = []
    var originRawValue: String = MemoryOrigin.user.rawValue
    var lastEvidenceAt: Date = Date()
    var confidence: Double?
    var expiresAt: Date?
    var supersedesID: UUID?

    init(
        draft: MemoryDraft,
        sourceCaptureIDs: [UUID] = [],
        supersedesID: UUID? = nil
    ) {
        kindRawValue = draft.kind.rawValue
        scopeRawValue = draft.scope.rawValue
        name = draft.name
        notes = draft.notes
        self.sourceCaptureIDs = sourceCaptureIDs
        self.supersedesID = supersedesID
    }

    var kind: MemoryKind? { MemoryKind(rawValue: kindRawValue) }
    var scope: MemoryScope? { MemoryScope(rawValue: scopeRawValue) }
    var status: MemoryStatus? { MemoryStatus(rawValue: statusRawValue) }
    var origin: MemoryOrigin? { MemoryOrigin(rawValue: originRawValue) }
    var archiveReason: MemoryArchiveReason? { archiveReasonRawValue.flatMap(MemoryArchiveReason.init(rawValue:)) }

    var draft: MemoryDraft? {
        guard let kind, let scope else { return nil }
        return MemoryDraft(kind: kind, name: name, notes: notes, scope: scope)
    }

    var snapshot: MemorySnapshot? {
        guard let kind, let scope, let status, let origin else { return nil }
        return MemorySnapshot(
            id: id,
            kind: kind,
            scope: scope,
            status: status,
            name: name,
            notes: notes,
            origin: origin,
            updatedAt: updatedAt,
            expiresAt: expiresAt
        )
    }
}

struct MemorySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MemoryKind
    let scope: MemoryScope
    let status: MemoryStatus
    let name: String
    let notes: String
    let origin: MemoryOrigin
    let updatedAt: Date
    let expiresAt: Date?
}

@Model
final class MemoryEvidenceRecord {
    var id: UUID = UUID()
    var memoryID: UUID = UUID()
    var sourceCaptureID: UUID = UUID()
    var sourceText: String = ""
    var claim: String = ""
    var capturedAt: Date = Date()
    var createdAt: Date = Date()
    var confidence: Double?

    init(
        memoryID: UUID,
        source: MemoryAnalysisSource,
        claim: String,
        confidence: Double?
    ) {
        self.memoryID = memoryID
        sourceCaptureID = source.captureID
        sourceText = source.text
        capturedAt = source.capturedAt
        self.claim = claim
        self.confidence = confidence
    }
}

struct MemoryEvidenceSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceCaptureID: UUID
    let sourceText: String
    let claim: String
    let capturedAt: Date
    let confidence: Double?

    init(_ record: MemoryEvidenceRecord) {
        id = record.id
        sourceCaptureID = record.sourceCaptureID
        sourceText = record.sourceText
        claim = record.claim
        capturedAt = record.capturedAt
        confidence = record.confidence
    }
}

enum MemoryText {
    static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
}
