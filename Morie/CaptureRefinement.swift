import Foundation

struct RefinementInput: Codable, Equatable, Sendable {
    var id = UUID()
    let captureID: UUID
    let text: String
    var context: [MemoryContextMatch] = []
    var dictionary: [DictionarySnapshot] = []
    // Optional by design: refinements created before Expression Profile, or
    // refinements that did not use a stable style profile, have no directives.
    // Treat absence exactly like an empty directive list.
    var expressionStyle: [String]?

    var effectiveExpressionStyle: [String] { expressionStyle ?? [] }
    var prepared: ValidatedRefinement { DictionarySpelling.normalize(text, using: dictionary) }
}

struct RefinementEdit: Codable, Equatable, Sendable {
    let original: String
    let replacement: String
    var dictionaryEntryID: UUID?
}

enum RefinementStatus: String, Codable, Sendable {
    case running, applied, unchanged, skipped, timedOut, failed, interrupted

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

enum RefinementReason: String, Codable, Error, Sendable {
    case disabled, modelBusy, unavailable, unsupportedLanguage, textTooLong
    case declined, generationFailed, invalidEdits, memoryChanged, dictionaryChanged, expressionStyleChanged
    case timeLimit, interrupted, saveFailed

    var message: String {
        switch self {
        case .disabled: "AI 润色已关闭，自定义字典仍然生效。"
        case .modelBusy: "前一次本机分析尚未结束，本次使用字典修正后的文字继续输入。"
        case .unavailable: "Apple 智能暂不可用，本次使用字典修正后的文字继续输入。"
        case .unsupportedLanguage: "本机模型暂不支持润色这种语言，已保留保存的文字。"
        case .textTooLong: "输入内容超过单次本机处理范围，已保留完整文字。"
        case .declined: "Apple 智能未能处理本次润色，已保留保存的文字。"
        case .generationFailed: "AI 润色未能完成，已保留保存的文字。"
        case .invalidEdits: "AI 未返回有效文字，已使用字典修正后的文字继续输入。"
        case .memoryChanged: "润色期间个人记忆发生变化，已使用字典修正后的文字继续输入。"
        case .dictionaryChanged: "润色期间字典发生变化，已保留识别文字。"
        case .expressionStyleChanged: "润色期间表达习惯发生变化，已使用当前保存的文字继续输入。"
        case .timeLimit: "AI 润色超时，已使用字典修正后的文字继续输入。"
        case .interrupted: "输入处理已中断，已保存的文字和录音均已保留。"
        case .saveFailed: "无法保存处理结果，已保留此前保存的文字。"
        }
    }

    var status: RefinementStatus {
        switch self {
        case .disabled, .modelBusy, .unavailable, .unsupportedLanguage, .textTooLong: .skipped
        case .timeLimit: .timedOut
        case .interrupted: .interrupted
        default: .failed
        }
    }
}

struct CaptureRefinement: Codable, Equatable, Sendable {
    let input: RefinementInput
    let startedAt: Date
    var status: RefinementStatus = .running
    var reason: RefinementReason?
    var durationSeconds: Double?
    var edits: [RefinementEdit] = []

    var preservesFinalText: Bool { status == .applied || status == .unchanged || !edits.isEmpty }
}

struct ValidatedRefinement: Equatable, Sendable {
    let text: String
    let edits: [RefinementEdit]
}

extension ValidatedRefinement {
    /// Foundation Models owns the cleanup decision. This boundary checks only that
    /// its structured text payload is usable before it is saved and delivered.
    static func accepting(_ proposedText: String, for input: RefinementInput) throws -> ValidatedRefinement {
        let prepared = input.prepared
        let output = proposedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty,
              !output.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" && $0 != "\r" })
        else { throw RefinementReason.invalidEdits }
        if output == prepared.text { return prepared }
        let cleanup = RefinementEdit(original: prepared.text, replacement: output)
        return ValidatedRefinement(text: output, edits: prepared.edits + [cleanup])
    }
}
