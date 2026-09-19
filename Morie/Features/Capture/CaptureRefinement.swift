import Foundation

struct RefinementInput: Codable, Equatable, Sendable {
    var id = UUID()
    let captureID: UUID
    let text: String
    var context: [MemoryContextMatch] = []
    var dictionary: [DictionarySnapshot] = []
    var corrections: [DictionaryCorrectionSnapshot]? = nil
    var expressionStyle: [String] = []

    var confirmedCorrections: [DictionaryCorrectionSnapshot] { corrections ?? [] }

    var prepared: ValidatedRefinement {
        let corrected = DictionaryCorrections.apply(text, using: confirmedCorrections)
        let normalized = DictionarySpelling.normalize(corrected.text, using: dictionary)
        return ValidatedRefinement(
            text: normalized.text,
            edits: corrected.edits + normalized.edits
        )
    }
}

struct RefinementEdit: Codable, Equatable, Sendable {
    let original: String
    let replacement: String
    var dictionaryEntryID: UUID? = nil
    var correctionRuleID: UUID? = nil
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
        guard isGrounded(output, in: prepared.text) else {
            throw RefinementReason.invalidEdits
        }
        let cleanup = RefinementEdit(original: prepared.text, replacement: output)
        return ValidatedRefinement(text: output, edits: prepared.edits + [cleanup])
    }

    private static func isGrounded(_ output: String, in source: String) -> Bool {
        let sourceCharacters = semanticCharacters(in: source)
        guard !sourceCharacters.isEmpty else { return false }

        let sentenceSeparators = CharacterSet(charactersIn: "。！？!?；;\n\r")
        let sentences = output.components(separatedBy: sentenceSeparators)
        for sentence in sentences {
            let candidate = semanticCharacters(in: sentence)
            // Short corrections are where ASR cleanup legitimately changes the
            // highest percentage of characters. The guard targets whole new
            // clauses/sentences, not a two-character homophone repair.
            guard candidate.count >= 8 else { continue }
            let overlap = longestCommonSubsequenceLength(candidate, sourceCharacters)
            let ratio = Double(overlap) / Double(candidate.count)
            guard ratio >= 0.42 else { return false }
        }
        return true
    }

    private static func semanticCharacters(in text: String) -> [Character] {
        text.filter { character in
            character.unicodeScalars.contains { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || (0x3400...0x4DBF).contains(scalar.value)
                    || (0x4E00...0x9FFF).contains(scalar.value)
                    || (0xF900...0xFAFF).contains(scalar.value)
            }
        }
    }

    private static func longestCommonSubsequenceLength(
        _ lhs: [Character],
        _ rhs: [Character]
    ) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: rhs.count + 1)
        for left in lhs {
            var current = Array(repeating: 0, count: rhs.count + 1)
            for (index, right) in rhs.enumerated() {
                if left == right {
                    current[index + 1] = previous[index] + 1
                } else {
                    current[index + 1] = max(current[index], previous[index + 1])
                }
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
