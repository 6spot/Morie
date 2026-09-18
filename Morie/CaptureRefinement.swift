import Foundation

struct RefinementInput: Codable, Equatable, Sendable {
    var id = UUID()
    let captureID: UUID
    let text: String
    var context: [MemoryContextMatch] = []
    var dictionary: [DictionarySnapshot] = []

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
    case declined, generationFailed, invalidEdits, memoryChanged, dictionaryChanged
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
        case .invalidEdits: "润色结果未通过内容检查，已使用字典修正后的文字继续输入。"
        case .memoryChanged: "润色期间个人记忆发生变化，已使用字典修正后的文字继续输入。"
        case .dictionaryChanged: "润色期间字典发生变化，已保留识别文字。"
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

enum RefinementValidator {
    /// Content checks complement the model instructions; they do not prove semantic equivalence.
    /// Cleanup may remove filler/redundancy and format existing structure, but cannot add content words.
    static func validate(_ proposedText: String, for input: RefinementInput) throws -> ValidatedRefinement {
        let prepared = input.prepared
        let output = proposedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, output.count <= max(64, prepared.text.count * 2),
              !output.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" && $0 != "\r" })
        else { throw RefinementReason.invalidEdits }
        if output == prepared.text { return prepared }

        let source = prepared.text
        let before = units(source)
        let after = units(output)
        guard !after.isEmpty, isSubsequence(after, of: before),
              after.count >= max(1, before.count / 3) else { throw RefinementReason.invalidEdits }

        // A clear local repair such as “周三，不，周四” may remove the abandoned date and “不”.
        // Ambiguous alternatives keep both values; numerical changes are otherwise rejected.
        let repairedSource = removingExplicitCorrections(source)
        guard numericTokens(repairedSource) == numericTokens(output),
              protectedTokens(source) == protectedTokens(output) else { throw RefinementReason.invalidEdits }

        let meaningful = ["不", "没", "别", "未", "可能", "也许", "或许", "大概", "觉得", "好像", "似乎", "或者", "还是", "吧", "吗", "呢",
                          "not", "no", "never", "without", "maybe", "perhaps", "probably", "might", "could", "guess", "think", "or", "if", "unless"]
        for term in meaningful {
            guard occurrences(term, in: repairedSource) == occurrences(term, in: output) else { throw RefinementReason.invalidEdits }
        }
        // Complete acknowledgments and intentional repeated emphasis are not filler.
        let acknowledgments: Set<String> = ["嗯", "好", "好的", "是", "是的", "对", "对的", "ok", "okay", "yes", "no"]
        if (before.allSatisfy({ acknowledgments.contains($0) }) || acknowledgments.contains(before.joined())) && before != after {
            throw RefinementReason.invalidEdits
        }
        for term in ["非常", "一定", "真的", "特别", "very", "really"] where occurrences(term, in: source) > 1 {
            guard occurrences(term, in: source) == occurrences(term, in: output) else { throw RefinementReason.invalidEdits }
        }
        for marks in [["?", "？"], ["!", "！"]] where marks.contains(where: source.contains) {
            guard marks.contains(where: output.contains) else { throw RefinementReason.invalidEdits }
        }
        let cleanup = RefinementEdit(original: source, replacement: output)
        return ValidatedRefinement(text: output, edits: prepared.edits + [cleanup])
    }

    private static func withoutListMarkers(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(?m)^[\t ]*(?:[-*•]|\d{1,3}[.)、])[\t ]+"#) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: "")
    }

    private static func units(_ text: String) -> [String] {
        let text = withoutListMarkers(text)
        return InputText.words(in: text).flatMap { range -> [String] in
            let word = String(text[range]).lowercased()
            if word.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) { return word.map(String.init) }
            return [word]
        }
    }

    private static func isSubsequence(_ candidate: [String], of source: [String]) -> Bool {
        var next = 0
        for unit in source where next < candidate.count {
            if unit == candidate[next] { next += 1 }
        }
        return next == candidate.count
    }

    private static func occurrences(_ term: String, in text: String) -> Int {
        if term.unicodeScalars.allSatisfy({ $0.isASCII }) { return InputText.literalRanges(of: term, in: text).count }
        return text.components(separatedBy: term).count - 1
    }

    private static func numericTokens(_ text: String) -> [String] {
        let text = withoutListMarkers(text)
        return InputText.ranges(#"\d+(?:[.,:/-]\d+)*|(?:周|星期)[一二三四五六日天]|[零一二三四五六七八九十百千万亿两]+(?:年|月|日|号|点|个|元|次|天|小时|分钟)"#, in: text).map { String(text[$0]) }
    }

    private static func protectedTokens(_ text: String) -> [String] {
        InputText.technicalRanges(in: text).map { String(text[$0]) }
    }

    private static func removingExplicitCorrections(_ text: String) -> String {
        let value = #"(?:周[一二三四五六日天]|星期[一二三四五六日天]|\d+(?:\.\d+)?(?:年|月|日|号|点|个|元|次|天)?)"#
        let pattern = "(" + value + #")[，,\s]+(?:不|不对|不是|改成|改为)[，,\s]+("# + value + ")"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: "$2")
    }
}
