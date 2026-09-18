import Combine
import Foundation

@MainActor
final class MemoryCandidateController: ObservableObject {
    typealias Extract = @Sendable (MemoryExtractionInput) async throws -> [MemorySuggestion]

    @Published private(set) var extractingCaptureID: UUID?
    @Published private(set) var messageCaptureID: UUID?
    @Published private(set) var message: String?
    @Published private(set) var isInputActive = false

    private let store: MemoryStore
    private let extract: Extract
    private let canUseModel: @MainActor () -> Bool
    private var extractionTask: Task<Void, Never>?

    init(
        store: MemoryStore, canUseModel: @escaping @MainActor () -> Bool = { true },
        extract: @escaping Extract = MemoryCandidateExtractor.extract
    ) {
        self.store = store
        self.extract = extract
        self.canUseModel = canUseModel
    }

    func findCandidates(for captureID: UUID, automatically: Bool = false) {
        guard !isInputActive, extractionTask == nil else { return }
        guard canUseModel() else {
            if !automatically {
                messageCaptureID = captureID
                message = "Earlier on-device analysis is still finishing. Your capture is saved; try again shortly."
            }
            return
        }
        messageCaptureID = captureID
        message = nil
        let input: MemoryExtractionInput
        do {
            input = try store.extractionInput(for: captureID)
            try store.load()
            if store.extraction(for: input) != nil {
                message = "This saved text has already been analyzed. Your review decisions have been kept."
                return
            }
        } catch {
            message = error.localizedDescription
            return
        }
        extractingCaptureID = captureID
        extractionTask = Task { [weak self, extract] in
            guard let self else { return }
            defer {
                self.extractingCaptureID = nil
                self.extractionTask = nil
            }
            do {
                let suggestions = try await extract(input)
                try Task.checkCancellation()
                guard !self.isInputActive else { throw CancellationError() }
                try self.store.saveCandidates(suggestions, for: input)
                self.message = self.store.extraction(for: input)?.candidates.isEmpty == true
                    ? "No high-confidence vocabulary or project suggestions were found. Your capture is saved."
                    : "Review each suggestion before saving it to Memory."
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self.message = "Memory extraction cancelled. Your capture is saved."
                } else if let error = error as? MemoryStore.StoreError {
                    self.message = error.localizedDescription
                } else if let error = error as? MemoryCandidateExtractor.ExtractionError {
                    self.message = error.localizedDescription
                } else {
                    self.message = "Memory extraction could not finish. Your capture and existing memories are saved. Try again."
                }
            }
        }
    }

    func cancelExtraction() { extractionTask?.cancel() }

    func setInputActive(_ active: Bool) {
        isInputActive = active
        if active { cancelExtraction() }
    }

    func waitForExtraction() async { await extractionTask?.value }
}
