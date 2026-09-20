import Foundation
import FoundationModels
import FoundationModelsUtilities

enum RefinementModelMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case local
    case cloud

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .local: "Apple 本机"
        case .cloud: "外部 API"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "优先使用已配置的外部模型，失败时回退 Apple 本机模型。"
        case .local: "始终使用这台 Mac 上的 Apple Foundation Models。"
        case .cloud: "始终使用已配置的 OpenAI-compatible Chat Completions API。"
        }
    }
}

struct RefinementModelConfiguration: Equatable, Sendable {
    let mode: RefinementModelMode
    let cloudBaseURL: String
    let cloudModelName: String
    let cloudAPIKey: String

    static let local = RefinementModelConfiguration(
        mode: .local,
        cloudBaseURL: "",
        cloudModelName: "",
        cloudAPIKey: ""
    )

    var cloudURL: URL? {
        let value = cloudBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }

    var trimmedCloudModelName: String {
        cloudModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUsableCloudConfiguration: Bool {
        cloudURL != nil && !trimmedCloudModelName.isEmpty
    }
}

enum InputRefiner {
    private struct PromptInputData: Encodable {
        let transcript: String
        let spellingCandidates: [String]
        let personalContext: [PromptMemoryHint]
        let expressionStyle: [String]
    }

    /// Topic-level Memory hints only. Raw Memory notes/evidence are deliberately
    /// excluded from refinement so Personal Memory can disambiguate without
    /// becoming a second source of user-authored output.
    private struct PromptMemoryHint: Encodable {
        let topic: String
        let matchedTerm: String
        let kind: String
        let scope: String
    }

    static func promptText(for input: RefinementInput) throws -> String {
        let data = try JSONEncoder().encode(PromptInputData(
            transcript: input.prepared.text,
            spellingCandidates: input.dictionary.map(\.name),
            personalContext: input.context.map {
                PromptMemoryHint(
                    topic: $0.memory.name,
                    matchedTerm: $0.matchedTerm,
                    kind: $0.memory.kind.rawValue,
                    scope: $0.memory.scope.rawValue
                )
            },
            expressionStyle: input.expressionStyle
        ))
        return String(decoding: data, as: UTF8.self)
    }


    static func generate(
        _ input: RefinementInput,
        configuration: RefinementConfiguration = .local
    ) async throws -> String {
        try Task.checkCancellation()
        let modelConfiguration = configuration.model
        switch modelConfiguration.mode {
        case .local:
            return try await generateLocally(
                input,
                instructionsText: configuration.instructions
            )
        case .cloud:
            return try await generateWithCloud(
                input,
                configuration: modelConfiguration,
                instructionsText: configuration.instructions
            )
        case .automatic:
            guard modelConfiguration.hasUsableCloudConfiguration else {
                return try await generateLocally(
                    input,
                    instructionsText: configuration.instructions
                )
            }
            do {
                return try await generateWithCloud(
                    input,
                    configuration: modelConfiguration,
                    instructionsText: configuration.instructions
                )
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                Diagnostics.record(
                    "Refinement",
                    "External refinement failed in Auto mode; falling back to Apple on-device model",
                    level: .warning
                )
                return try await generateLocally(
                    input,
                    instructionsText: configuration.instructions
                )
            }
        }
    }

    private static func generateLocally(
        _ input: RefinementInput,
        instructionsText: String
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { throw RefinementReason.unavailable }
        let instructions = Instructions { instructionsText }
        let promptText = try promptText(for: input)
        let prompt = Prompt { promptText }
        do {
            Diagnostics.recordMemory("refinement-local-before-token-count")
            let promptTokens = try await model.tokenCount(for: prompt)
            let instructionTokens = try await model.tokenCount(for: instructions)
            let schemaTokens = try await model.tokenCount(for: GeneratedRefinement.generationSchema)
            let responseBudget = min(1_536, max(256, promptTokens + 64))
            Diagnostics.recordMemory("refinement-local-after-token-count")
            guard promptTokens + instructionTokens + schemaTokens + responseBudget + 128 <= model.contextSize else {
                throw RefinementReason.textTooLong
            }
            try Task.checkCancellation()
            let text = try await generateLocalResponse(
                model: model,
                instructions: instructions,
                prompt: prompt,
                responseBudget: responseBudget
            )
            Diagnostics.recordMemory("refinement-local-session-scope-exited")
            return text
        } catch {
            if Task.isCancelled || error is CancellationError {
                Diagnostics.recordMemory("refinement-local-cancelled")
                throw CancellationError()
            }
            Diagnostics.recordMemory("refinement-local-failed")
            if let reason = error as? RefinementReason { throw reason }
            // Framework errors can contain private input. Persist only fixed reasons.
            switch error {
            case LanguageModelError.contextSizeExceeded: throw RefinementReason.textTooLong
            case LanguageModelError.unsupportedLanguageOrLocale: throw RefinementReason.unsupportedLanguage
            case LanguageModelError.refusal, LanguageModelError.guardrailViolation: throw RefinementReason.declined
            default: throw RefinementReason.generationFailed
            }
        }
    }

    private static func generateLocalResponse(
        model: SystemLanguageModel,
        instructions: Instructions,
        prompt: Prompt,
        responseBudget: Int
    ) async throws -> String {
        Diagnostics.recordMemory("refinement-local-before-session")
        let session = LanguageModelSession(model: model, instructions: instructions)
        Diagnostics.recordMemory("refinement-local-session-created")
        let response = try await session.respond(
            to: prompt, generating: GeneratedRefinement.self,
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: responseBudget)
        )
        Diagnostics.recordMemory("refinement-local-respond-finished")
        try Task.checkCancellation()
        return response.content.text
    }

    private static func generateWithCloud(
        _ input: RefinementInput,
        configuration: RefinementModelConfiguration,
        instructionsText: String
    ) async throws -> String {
        guard let url = configuration.cloudURL,
              !configuration.trimmedCloudModelName.isEmpty
        else { throw RefinementReason.unavailable }

        let key = configuration.cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let headers = key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"]
        let model = ChatCompletionsLanguageModel(
            name: configuration.trimmedCloudModelName,
            url: url,
            additionalHeaders: headers,
            supportsGuidedGeneration: false
        )
        let instructions = Instructions { instructionsText }
        let promptText = try promptText(for: input)
        let prompt = Prompt { promptText }
        let responseBudget = min(1_536, max(256, input.prepared.text.count * 2))

        do {
            try Task.checkCancellation()
            Diagnostics.recordMemory("refinement-cloud-before-session")
            let content = try await generateCloudResponse(
                model: model,
                instructions: instructions,
                prompt: prompt,
                responseBudget: responseBudget
            )
            Diagnostics.recordMemory("refinement-cloud-session-scope-exited")
            return content
        } catch {
            if Task.isCancelled || error is CancellationError {
                Diagnostics.recordMemory("refinement-cloud-cancelled")
                throw CancellationError()
            }
            Diagnostics.recordMemory("refinement-cloud-failed")
            // Remote errors may include response bodies. Never persist them into Capture history.
            throw RefinementReason.generationFailed
        }
    }

    private static func generateCloudResponse(
        model: ChatCompletionsLanguageModel,
        instructions: Instructions,
        prompt: Prompt,
        responseBudget: Int
    ) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        Diagnostics.recordMemory("refinement-cloud-session-created")
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: responseBudget)
        )
        Diagnostics.recordMemory("refinement-cloud-respond-finished")
        try Task.checkCancellation()
        return response.content
    }
}

@Generable
private struct GeneratedRefinement {
    @Guide(description: "整理后的最终正文。")
    var text: String
}

enum RefinementGeneration: Sendable {
    case text(String)
    case keptOriginal(RefinementReason)
}

/// One explicitly owned model task. Completion is model-driven; caller cancellation
/// still releases the input path without waiting for model cancellation to drain.
@MainActor
final class InputRefinementRunner {
    typealias Generate = @Sendable (RefinementInput, RefinementConfiguration) async throws -> String
    typealias LegacyGenerate = @Sendable (RefinementInput) async throws -> String

    private let generate: Generate
    private var generationTask: Task<Void, Never>?
    private var modelID: UUID?
    private var waitingID: UUID?
    private var continuation: CheckedContinuation<RefinementGeneration, Error>?

    var isBusy: Bool { generationTask != nil }

    // Observation for shutdown/validation only. The live input path never awaits model teardown.
    func waitForModelToFinish() async { await generationTask?.value }

    init() {
        generate = InputRefiner.generate
    }

    init(generate: @escaping Generate) {
        self.generate = generate
    }

    init(generate: @escaping LegacyGenerate) {
        self.generate = { input, _ in try await generate(input) }
    }

    func run(
        _ input: RefinementInput,
        configuration: RefinementConfiguration = .local
    ) async throws -> RefinementGeneration {
        try Task.checkCancellation()
        guard !isBusy else { return .keptOriginal(.modelBusy) }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                waitingID = id
                modelID = id
                generationTask = Task { [weak self, generate] in
                    let outcome: RefinementGeneration
                    do {
                        outcome = .text(try await generate(input, configuration))
                    } catch {
                        outcome = .keptOriginal((error as? RefinementReason) ?? .generationFailed)
                    }
                    self?.modelFinished(id, outcome: outcome)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishWaiting(id, result: .failure(CancellationError()), cancelModel: true)
            }
        }
    }

    private func modelFinished(_ id: UUID, outcome: RefinementGeneration) {
        guard modelID == id else { return }
        generationTask = nil
        modelID = nil
        finishWaiting(id, result: .success(outcome), cancelModel: false)
    }

    private func finishWaiting(_ id: UUID, result: Result<RefinementGeneration, Error>, cancelModel: Bool) {
        guard waitingID == id, let continuation else { return }
        self.continuation = nil
        waitingID = nil
        if cancelModel { generationTask?.cancel() }
        continuation.resume(with: result)
        // generationTask remains owned until it actually ends. New optional work must skip while busy.
    }
}
