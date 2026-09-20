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
        case .invalidEdits: "AI 润色结果越过了事实或意图安全边界，已使用字典修正后的文字继续输入。"
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
    /// The model owns wording, structure, and paragraphing. This boundary only
    /// rejects output when we can prove that it crossed a factual or intent
    /// invariant. Natural rewrites are deliberately not gated by text similarity.
    static func accepting(_ proposedText: String, for input: RefinementInput) throws -> ValidatedRefinement {
        let prepared = input.prepared
        let output = proposedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty,
              !output.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
                      && $0 != "\n"
                      && $0 != "\t"
                      && $0 != "\r"
              })
        else { throw RefinementReason.invalidEdits }

        if output == prepared.text { return prepared }
        try RefinementOutputGuard.validate(output, source: prepared.text, input: input)

        let cleanup = RefinementEdit(original: prepared.text, replacement: output)
        return ValidatedRefinement(text: output, edits: prepared.edits + [cleanup])
    }
}

/// Protects invariants that can be checked deterministically without constraining
/// how the model phrases or structures the user's text.
private enum RefinementOutputGuard {
    static func validate(_ output: String, source: String, input: RefinementInput) throws {
        guard !looksLikeAssistantAnswer(output, source: source) else {
            throw RefinementReason.invalidEdits
        }
        guard !claimsExecution(output, source: source) else {
            throw RefinementReason.invalidEdits
        }
        guard preservesSemanticRelations(output, source: source) else {
            throw RefinementReason.invalidEdits
        }
        guard preservesProtectedFacts(output, source: source, input: input) else {
            throw RefinementReason.invalidEdits
        }
        guard !introducesContextOnlyContent(output, source: source, input: input) else {
            throw RefinementReason.invalidEdits
        }
        guard !changesPrimaryScript(output, source: source) else {
            throw RefinementReason.invalidEdits
        }
        guard !isExtremeExpansion(output, source: source) else {
            throw RefinementReason.invalidEdits
        }
    }

    private static func looksLikeAssistantAnswer(_ output: String, source: String) -> Bool {
        let prefixes = [
            "答案是", "回答如下", "以下是", "建议如下", "我建议", "我可以帮你",
            "the answer is", "here is", "here's", "i recommend",
        ]
        let outputText = trimmingLeadingFillers(output)
        guard let prefix = prefixes.first(where: { startsWithPhrase(outputText, $0) }) else {
            return false
        }
        return !startsWithPhrase(trimmingLeadingFillers(source), prefix)
    }

    private static func claimsExecution(_ output: String, source: String) -> Bool {
        let claims = [
            "已经为你", "已为你", "操作完成", "已经完成", "已完成",
            "发送成功", "删除成功", "创建成功", "设置完成",
            "done", "completed successfully",
        ]
        let outputText = trimmingLeadingFillers(output)
        guard let claim = claims.first(where: { startsWithPhrase(outputText, $0) }) else {
            return false
        }
        return !startsWithPhrase(trimmingLeadingFillers(source), claim)
    }

    private static func preservesSemanticRelations(_ output: String, source: String) -> Bool {
        // Explicit self-corrections intentionally remove earlier negations/facts.
        guard !hasExplicitCorrectionSignal(source) else { return true }

        let relationGroups = [
            [
                "不要", "不能", "不得", "禁止", "不允许", "不可以", "不应该",
                "不需要", "不会", "不是", "没有", "没法", "没能", "没什么", "没啥",
                "do not", "don't", "must not", "never", "cannot", "can't",
                "won't", "not allowed", "without",
            ],
            [
                "如果", "若是", "假如", "假设", "要是", "只要", "除非",
                "if", "unless", "provided that", "as long as",
            ],
        ]

        for group in relationGroups {
            let sourceHasRelation = group.contains { containsPhrase(source, $0) }
            let outputHasRelation = group.contains { containsPhrase(output, $0) }
            if sourceHasRelation != outputHasRelation { return false }
        }
        return true
    }

    private static func preservesProtectedFacts(
        _ output: String,
        source: String,
        input: RefinementInput
    ) -> Bool {
        let knownTerms = input.dictionary.map(\.name) + input.context.map(\.memory.name)
        let sourceFacts = protectedFacts(in: source, knownTerms: knownTerms)
        let outputFacts = protectedFacts(in: output, knownTerms: knownTerms)

        if hasExplicitCorrectionSignal(source) {
            // A correction such as "15，不，16个" may legitimately drop the
            // superseded fact, but it still has to retain at least one factual
            // anchor from the spoken source.
            if !sourceFacts.isEmpty && sourceFacts.isDisjoint(with: outputFacts) {
                return false
            }
        } else if !sourceFacts.isSubset(of: outputFacts) {
            return false
        }

        // Dictionary words and memory names may repair an ASR spelling, but no
        // other number, URL, weekday, version, path, or identifier may appear
        // out of nowhere.
        let hintFacts = protectedFacts(
            in: knownTerms.joined(separator: "\n"),
            knownTerms: knownTerms
        )
        let additions = outputFacts.subtracting(sourceFacts).subtracting(hintFacts)
        return additions.isEmpty
    }

    private static func protectedFacts(in text: String, knownTerms: [String]) -> Set<String> {
        let text = removingListMarkers(from: text)
        var facts = Set<String>()
        let patterns = [
            #"https?://[^\s<>"']+"#,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?:/[A-Za-z0-9._-]+){2,}"#,
            #"(?<![A-Za-z0-9_])\d+(?:\.\d+)?(?![A-Za-z0-9_])"#,
            #"(?:周|星期|礼拜)[一二三四五六日天]"#,
        ]
        for pattern in patterns {
            for match in regexMatches(pattern, in: text) {
                facts.insert(canonicalFact(match))
            }
        }
        for token in protectedIdentifierTokens(in: text) {
            facts.insert(canonicalFact(token))
        }
        for term in knownTerms {
            let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            else { continue }
            facts.insert("term:" + value.lowercased())
        }
        return facts
    }

    private static func protectedIdentifierTokens(in text: String) -> [String] {
        regexMatches(#"(?<![A-Za-z0-9_])[A-Za-z][A-Za-z0-9_.+-]{1,}(?![A-Za-z0-9_])"#, in: text)
            .filter { token in
                let scalars = token.unicodeScalars
                let hasUpper = scalars.contains { CharacterSet.uppercaseLetters.contains($0) }
                let hasLower = scalars.contains { CharacterSet.lowercaseLetters.contains($0) }
                let tailHasUpper = token.dropFirst().unicodeScalars.contains {
                    CharacterSet.uppercaseLetters.contains($0)
                }
                let hasDigit = scalars.contains { CharacterSet.decimalDigits.contains($0) }
                let allCaps = hasUpper && !hasLower && token.count >= 2
                let mixedCase = hasUpper && hasLower && tailHasUpper
                let identifierPunctuation = token.contains("_") || token.contains("-")
                return allCaps || mixedCase || hasDigit || identifierPunctuation
            }
    }

    private static func introducesContextOnlyContent(
        _ output: String,
        source: String,
        input: RefinementInput
    ) -> Bool {
        let sourceSemantic = semanticText(source)
        let outputSemantic = semanticText(output)
        guard !outputSemantic.isEmpty else { return false }

        let separators = CharacterSet(charactersIn: "。！？!?；;\n\r")
        for match in input.context {
            for clause in match.memory.notes.components(separatedBy: separators) {
                let candidate = semanticText(clause)
                let counts = scriptCounts(candidate)
                let meaningful = counts.cjk >= 4 || (counts.cjk == 0 && counts.latin >= 12)
                guard meaningful else { continue }
                if outputSemantic.contains(candidate) && !sourceSemantic.contains(candidate) {
                    return true
                }
            }
        }
        return false
    }

    private static func changesPrimaryScript(_ output: String, source: String) -> Bool {
        let sourceCounts = scriptCounts(source)
        let outputCounts = scriptCounts(output)
        guard sourceCounts.total >= 8, outputCounts.total >= 8 else { return false }

        if sourceCounts.cjk >= 4, outputCounts.cjk == 0 { return true }

        let sourceCJKRatio = Double(sourceCounts.cjk) / Double(sourceCounts.total)
        let outputCJKRatio = Double(outputCounts.cjk) / Double(outputCounts.total)
        return (sourceCJKRatio >= 0.65 && outputCJKRatio <= 0.2)
            || (sourceCJKRatio <= 0.2 && outputCJKRatio >= 0.65)
    }

    private static func isExtremeExpansion(_ output: String, source: String) -> Bool {
        let sourceCount = max(1, semanticText(source).count)
        let outputCount = semanticText(output).count
        let ratioLimit = sourceCount * 5 / 2
        let absoluteLimit = sourceCount + 48
        return outputCount > max(ratioLimit, absoluteLimit)
    }

    private static func hasExplicitCorrectionSignal(_ text: String) -> Bool {
        let phrases = [
            "不对", "不是", "改成", "应该是", "准确说", "更正", "哦不",
            "i mean", "sorry, no", "rather",
        ]
        if phrases.contains(where: { containsPhrase(text, $0) }) { return true }
        return !regexMatches(#"[，,]\s*不\s*[，,]"#, in: text).isEmpty
    }

    private static func trimmingLeadingFillers(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fillers = ["嗯", "呃", "啊", "那个", "就是说", "就是"]
        for _ in 0..<4 {
            guard let filler = fillers.first(where: { value.hasPrefix($0) }) else { break }
            value.removeFirst(filler.count)
            value = value.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "，,。.!！?？：:")
                )
            )
        }
        return value
    }

    private static func startsWithPhrase(_ text: String, _ phrase: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)^"# + escaped + #"(?![A-Za-z0-9_])"#
        return !regexMatches(pattern, in: value).isEmpty
    }

    private static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        let isASCII = phrase.unicodeScalars.allSatisfy { $0.value < 128 }
        if !isASCII {
            return text.contains(phrase)
        }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)(?<![A-Za-z0-9_])"# + escaped + #"(?![A-Za-z0-9_])"#
        return !regexMatches(pattern, in: text).isEmpty
    }

    private static func removingListMarkers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^\s*\d+[.)、]\s+"#) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func canonicalFact(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,，。;；!?！？)]}"))
            .lowercased()
    }

    private static func regexMatches(
        _ pattern: String,
        in text: String
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func semanticText(_ text: String) -> String {
        String(text.lowercased().filter { character in
            character.unicodeScalars.contains { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || (0x3400...0x4DBF).contains(scalar.value)
                    || (0x4E00...0x9FFF).contains(scalar.value)
                    || (0xF900...0xFAFF).contains(scalar.value)
            }
        })
    }

    private static func scriptCounts(_ text: String) -> (cjk: Int, latin: Int, total: Int) {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value) {
                cjk += 1
            } else if (0x41...0x5A).contains(scalar.value)
                || (0x61...0x7A).contains(scalar.value) {
                latin += 1
            }
        }
        return (cjk, latin, cjk + latin)
    }
}
