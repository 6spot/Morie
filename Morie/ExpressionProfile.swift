import Foundation
import SwiftData

enum ExpressionFeature: String, Codable, CaseIterable, Sendable {
    case averageSentenceLength
    case lineBreakDensity
    case listUsage
    case terminalPunctuationUsage
    case exclamationUsage
    case chineseEnglishSpacing
}

enum ExpressionLearningState: String, Codable, Sendable {
    case insufficient
    case learning
    case stable
}

struct ExpressionFeatureAccumulator: Codable, Equatable, Sendable {
    var weightedMean: Double = 0
    var totalWeight: Double = 0
    var positiveEvidence = 0
    var negativeEvidence = 0
    var neutralEvidence = 0
    var firstObservedAt: Date?
    var updatedAt: Date = .distantPast
    var state: ExpressionLearningState = .insufficient
}

struct ExpressionProfileSnapshot: Codable, Equatable, Sendable {
    var sampleCount = 0
    var firstObservedAt: Date?
    var lastObservedAt: Date?
    var features: [String: ExpressionFeatureAccumulator] = [:]
}

@Model
final class ExpressionProfileRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var snapshot = ExpressionProfileSnapshot()

    init() {}
}

struct ExpressionStyleSample: Equatable, Sendable {
    let values: [ExpressionFeature: Double]
    let directions: [ExpressionFeature: Int]
}

enum ExpressionStyleExtractor {
    static func extract(injected: String, edited: String) -> ExpressionStyleSample? {
        let injected = injected.trimmingCharacters(in: .whitespacesAndNewlines)
        let edited = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard injected != edited,
              (8...1_200).contains(injected.utf16.count),
              (8...1_264).contains(edited.utf16.count),
              lexicalProjection(injected) == lexicalProjection(edited)
        else { return nil }

        var before = measurements(injected)
        var after = measurements(edited)
        for feature in [ExpressionFeature.listUsage, .chineseEnglishSpacing] {
            if before[feature] != nil || after[feature] != nil {
                before[feature] = before[feature] ?? 0
                after[feature] = after[feature] ?? 0
            }
        }
        let directions = Dictionary(uniqueKeysWithValues: ExpressionFeature.allCases.map { feature in
            let delta = (after[feature] ?? 0) - (before[feature] ?? 0)
            let epsilon = feature == .averageSentenceLength ? 1.0 : 0.025
            return (feature, delta > epsilon ? 1 : (delta < -epsilon ? -1 : 0))
        })
        return ExpressionStyleSample(values: after, directions: directions)
    }

    private static func measurements(_ text: String) -> [ExpressionFeature: Double] {
        let scalarCount = max(1, text.unicodeScalars.count)
        let sentenceCount = max(1, text.split(whereSeparator: { ".!?。！？\n".contains($0) }).count)
        let lines = text.components(separatedBy: .newlines)
        let nonemptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let listLines = nonemptyLines.filter {
            $0.range(of: #"^\s*(?:[-*•]|\d+[.)、])\s+"#, options: .regularExpression) != nil
        }
        let terminalPunctuation = nonemptyLines.filter {
            $0.trimmingCharacters(in: .whitespaces).last.map { ".!?。！？".contains($0) } == true
        }.count
        let exclamations = text.filter { "!！".contains($0) }.count
        let transitions = matches(#"(?:\p{Han}\s*[A-Za-z]|[A-Za-z]\s*\p{Han})"#, in: text)
        let spacedTransitions = matches(#"(?:\p{Han}\s+[A-Za-z]|[A-Za-z]\s+\p{Han})"#, in: text)

        var result: [ExpressionFeature: Double] = [
            .averageSentenceLength: Double(scalarCount) / Double(sentenceCount),
            .lineBreakDensity: Double(text.filter { $0 == "\n" }.count) / Double(scalarCount),
            .terminalPunctuationUsage: Double(terminalPunctuation) / Double(max(1, nonemptyLines.count)),
            .exclamationUsage: Double(exclamations) / Double(scalarCount),
        ]
        if listLines.count >= 2 {
            result[.listUsage] = Double(listLines.count) / Double(max(1, nonemptyLines.count))
        }
        if transitions > 0 {
            result[.chineseEnglishSpacing] = Double(spacedTransitions) / Double(transitions)
        }
        return result
    }

    private static func lexicalProjection(_ text: String) -> String {
        let withoutListMarkers = text.replacingOccurrences(
            of: #"(?m)^\s*(?:[-*•]|\d+[.)、])\s*"#,
            with: "",
            options: .regularExpression
        )
        let folded = withoutListMarkers.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let scalars = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func matches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }
}

@MainActor
final class ExpressionProfileStore {
    static let enabledDefaultsKey = "expressionProfileLearningEnabled"

    private let context: ModelContext
    private let learningSamples = 5
    private let stableSamples = 10
    private let stableDaySpan = 3

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func record(injected: String, edited: String, at date: Date = Date()) throws {
        guard let sample = ExpressionStyleExtractor.extract(injected: injected, edited: edited) else { return }
        let record = try profileRecord()
        var snapshot = record.snapshot
        snapshot.sampleCount += 1
        snapshot.firstObservedAt = min(snapshot.firstObservedAt ?? date, date)
        snapshot.lastObservedAt = max(snapshot.lastObservedAt ?? date, date)

        for feature in ExpressionFeature.allCases {
            guard let value = sample.values[feature],
                  let direction = sample.directions[feature],
                  direction != 0
            else { continue }

            var accumulator = snapshot.features[feature.rawValue] ?? ExpressionFeatureAccumulator()
            let totalWeight = accumulator.totalWeight + 1
            accumulator.weightedMean = ((accumulator.weightedMean * accumulator.totalWeight) + value) / totalWeight
            accumulator.totalWeight = totalWeight
            if direction > 0 {
                accumulator.positiveEvidence += 1
            } else {
                accumulator.negativeEvidence += 1
            }
            accumulator.firstObservedAt = min(accumulator.firstObservedAt ?? date, date)
            accumulator.updatedAt = date
            accumulator.state = learningState(for: accumulator)
            snapshot.features[feature.rawValue] = accumulator
        }

        record.snapshot = snapshot
        record.updatedAt = date
        try save()
    }

    func directives() throws -> [String] {
        guard let record = try existingRecord() else { return [] }
        let stable = Dictionary(uniqueKeysWithValues: ExpressionFeature.allCases.compactMap { feature -> (ExpressionFeature, ExpressionFeatureAccumulator)? in
            guard let value = record.snapshot.features[feature.rawValue], value.state == .stable else { return nil }
            return (feature, value)
        })
        var output: [String] = []

        if let value = stable[.averageSentenceLength]?.weightedMean {
            if value < 22 {
                output.append("倾向较短的句子，不要把多个意思合成长句。")
            } else if value > 42 {
                output.append("倾向保留自然完整的长句，不做不必要拆分。")
            }
        }
        if let value = stable[.lineBreakDensity]?.weightedMean, value > 0.025 {
            output.append("有清晰语义边界时倾向自然分段。")
        }
        if let value = stable[.listUsage]?.weightedMean {
            if value > 0.2 {
                output.append("原话包含多个明确要点时，倾向使用简洁列表。")
            } else if value < 0.03 {
                output.append("倾向连续自然段，除非原话明确要求列表。")
            }
        }
        if let value = stable[.terminalPunctuationUsage]?.weightedMean {
            output.append(value >= 0.65 ? "倾向保留句末标点。" : "非正式短句通常不强制补句末标点。")
        }
        if let value = stable[.exclamationUsage]?.weightedMean, value > 0.02 {
            output.append("原话带有感叹语气时，倾向保留感叹号。")
        }
        if let value = stable[.chineseEnglishSpacing]?.weightedMean {
            output.append(value >= 0.65 ? "中文与英文之间倾向保留空格。" : "不要自动在中文与英文之间添加空格。")
        }
        return Array(output.prefix(4))
    }

    func clear() throws {
        if let record = try existingRecord() {
            context.delete(record)
            try save()
        }
    }

    func snapshotForTesting() throws -> ExpressionProfileSnapshot {
        try existingRecord()?.snapshot ?? ExpressionProfileSnapshot()
    }

    private func learningState(
        for accumulator: ExpressionFeatureAccumulator
    ) -> ExpressionLearningState {
        let evidence = accumulator.positiveEvidence + accumulator.negativeEvidence
        guard evidence >= learningSamples else { return .insufficient }
        guard evidence >= stableSamples,
              let first = accumulator.firstObservedAt,
              Calendar.current.dateComponents([.day], from: first, to: accumulator.updatedAt).day ?? 0 >= stableDaySpan
        else { return .learning }

        let dominant = max(accumulator.positiveEvidence, accumulator.negativeEvidence)
        return Double(dominant) / Double(evidence) >= 0.7 ? .stable : .learning
    }

    private func profileRecord() throws -> ExpressionProfileRecord {
        if let existing = try existingRecord() { return existing }
        let record = ExpressionProfileRecord()
        context.insert(record)
        return record
    }

    private func existingRecord() throws -> ExpressionProfileRecord? {
        var descriptor = FetchDescriptor<ExpressionProfileRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func save() throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
