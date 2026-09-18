import Foundation
import NaturalLanguage

struct RefinementInput: Codable, Equatable, Sendable {
    var id = UUID()
    let captureID: UUID
    let text: String
    let context: [MemoryContextMatch]
}

struct RefinementProposal: Codable, Equatable, Sendable {
    let original: String
    let replacement: String
    // One-based occurrence in the original transcript, before applying any edits.
    var occurrence: Int = 1
}

struct RefinementEdit: Codable, Equatable, Sendable {
    let proposal: RefinementProposal
    // nil denotes punctuation/spacing cleanup, never an inferred vocabulary correction.
    let memoryID: UUID?
}

enum RefinementStatus: String, Codable, Sendable {
    case running, applied, unchanged, skipped, timedOut, failed, interrupted

    var title: String {
        switch self {
        case .running: "Refining…"
        case .applied: "Refined"
        case .unchanged: "Unchanged"
        case .skipped: "Skipped"
        case .timedOut: "Time Limit Reached"
        case .failed: "Original Text Kept"
        case .interrupted: "Interrupted"
        }
    }
}

enum RefinementReason: String, Codable, Error, Sendable {
    case disabled, modelBusy, unavailable, unsupportedLanguage, textTooLong
    case declined, generationFailed, invalidEdits, memoryChanged, contextUnavailable
    case timeLimit, interrupted, saveFailed

    var message: String {
        switch self {
        case .disabled: "Input refinement was turned off."
        case .modelBusy: "Earlier on-device analysis was still finishing. The original text was kept."
        case .unavailable: "Apple Intelligence was unavailable. The original text was kept."
        case .unsupportedLanguage: "The on-device model could not refine this language. The original text was kept."
        case .textTooLong: "The full input did not fit in one on-device request. The original text was kept."
        case .declined: "Apple Intelligence declined this refinement. The original text was kept."
        case .generationFailed: "Refinement could not finish. The original text was kept."
        case .invalidEdits: "Suggested changes could not be verified. The original text was kept."
        case .memoryChanged: "Relevant memory changed during refinement. The original text was kept."
        case .contextUnavailable: "Relevant memory could not be read. The original text was kept."
        case .timeLimit: "Refinement reached its time limit. The original text was kept to finish input promptly."
        case .interrupted: "Refinement was interrupted. Saved text and audio were kept."
        case .saveFailed: "The refined result could not be saved. The previously saved text was kept."
        }
    }

    var status: RefinementStatus {
        switch self {
        case .disabled, .modelBusy, .unavailable, .unsupportedLanguage, .textTooLong, .contextUnavailable: .skipped
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

    var preservesFinalText: Bool { status == .applied || status == .unchanged }
}

struct ValidatedRefinement: Equatable, Sendable {
    let text: String
    let edits: [RefinementEdit]
}

enum RefinementValidator {
    /// Validate against the immutable request, then apply all edits together. No partial rewrite.
    static func validate(_ proposals: [RefinementProposal], for input: RefinementInput) throws -> ValidatedRefinement {
        guard proposals.count <= 8 else { throw RefinementReason.invalidEdits }
        let source = input.text
        let words = wordRanges(in: source)
        let protected = protectedRanges(in: source)
        var accepted: [(Range<String.Index>, RefinementEdit)] = []

        for proposal in proposals {
            guard !proposal.original.isEmpty, proposal.original.count <= 160,
                  !proposal.replacement.isEmpty, proposal.replacement.count <= 180,
                  proposal.original != proposal.replacement,
                  (1...8).contains(proposal.occurrence),
                  let range = occurrence(of: proposal.original, number: proposal.occurrence, in: source),
                  !protected.contains(where: { $0.overlaps(range) }),
                  !accepted.contains(where: { $0.0.overlaps(range) }) else {
                throw RefinementReason.invalidEdits
            }

            let matchingMemory = input.context.map(\.memory).filter { memory in
                memory.status == .active && memory.userConfirmed
                    && memory.name == proposal.replacement
                    && ([memory.name] + memory.aliases).contains {
                        MemoryText.normalized($0) == MemoryText.normalized(proposal.original)
                    }
            }
            let memoryID: UUID?
            if matchingMemory.count == 1,
               !proposal.original.contains(where: \.isNewline),
               proposal.original == proposal.original.trimmingCharacters(in: .whitespacesAndNewlines),
               !words.contains(where: { splits($0, at: range) }) {
                memoryID = matchingMemory[0].id
            } else {
                guard isCleanup(proposal.original, proposal.replacement),
                      !words.contains(where: { splits($0, at: range) }) else {
                    throw RefinementReason.invalidEdits
                }
                var changed = source
                changed.replaceSubrange(range, with: proposal.replacement)
                guard words.map({ String(source[$0]) }) == wordRanges(in: changed).map({ String(changed[$0]) }) else {
                    throw RefinementReason.invalidEdits
                }
                memoryID = nil
            }
            accepted.append((range, RefinementEdit(proposal: proposal, memoryID: memoryID)))
        }

        accepted.sort { $0.0.lowerBound < $1.0.lowerBound }
        var result = source
        for (range, edit) in accepted.reversed() {
            result.replaceSubrange(range, with: edit.proposal.replacement)
        }
        return ValidatedRefinement(text: result, edits: accepted.map(\.1))
    }

    private static func occurrence(of phrase: String, number: Int, in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        for index in 1...number {
            guard let range = text.range(of: phrase, options: .literal, range: start..<text.endIndex) else { return nil }
            if index == number { return range }
            start = range.upperBound
        }
        return nil
    }

    private static func splits(_ word: Range<String.Index>, at range: Range<String.Index>) -> Bool {
        (word.lowerBound < range.lowerBound && range.lowerBound < word.upperBound)
            || (word.lowerBound < range.upperBound && range.upperBound < word.upperBound)
    }

    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        return ranges
    }

    private static func isCleanup(_ original: String, _ replacement: String) -> Bool {
        // Keep every content character, word boundary, newline and existing punctuation.
        // Only horizontal spacing and a missing comma/period may be added or tidied.
        let punctuation: Set<Character> = [",", "，", ".", "。"]
        func parts(_ text: String) -> (content: [Character], gaps: [String]) {
            var content: [Character] = []
            var gaps = [""]
            for character in text {
                if punctuation.contains(character) || character == " " || character == "\t" {
                    if punctuation.contains(character) { gaps[gaps.count - 1].append(character) }
                } else {
                    content.append(character)
                    gaps.append("")
                }
            }
            return (content, gaps)
        }
        let before = parts(original)
        let after = parts(replacement)
        guard !before.content.isEmpty, before.content == after.content,
              wordRanges(in: original).map({ String(original[$0]) })
                == wordRanges(in: replacement).map({ String(replacement[$0]) }) else { return false }
        return zip(before.gaps, after.gaps).enumerated().allSatisfy { index, pair in
            if pair.0 == pair.1 { return true }
            // Do not change/relocate punctuation or add leading punctuation.
            return index > 0 && pair.0.isEmpty && pair.1.count == 1
                && before.content[index - 1].isLetter
                && (index == before.content.count || before.content[index].isLetter || before.content[index].isNewline)
        }
    }

    private static func protectedRanges(in text: String) -> [Range<String.Index>] {
        // Code spans/blocks stay untouched. No language/provider/app-specific rewriting rules.
        if text.contains("`") { return [text.startIndex..<text.endIndex] }
        let syntax = CharacterSet(charactersIn: "/\\@_=$<>[]{}|^~+-\"'&;%")
        // A whitespace-delimited numeric or technical token is immutable, including its punctuation.
        return text.ranges(of: /\S+/).filter { range in
            let token = text[range]
            return token.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) || syntax.contains($0) })
                || token.contains(":")
                || token.dropLast().contains(".")
        }
    }
}
