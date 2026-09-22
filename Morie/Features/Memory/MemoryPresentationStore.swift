import Combine
import Foundation

@MainActor
final class MemoryPresentationStore: ObservableObject {
    enum StoreError: LocalizedError {
        case memoryUnavailable
        var errorDescription: String? { "此个人记忆已不存在。" }
    }

    @Published private(set) var entries: [MorieMemoryDTO] = []
    private let client: MorieRuntimeClient
    private var hasLoaded = false

    init(client: MorieRuntimeClient) {
        self.client = client
    }

    func loadIfNeeded() async throws {
        guard !hasLoaded else { return }
        try await load()
    }

    func load() async throws {
        entries = try await client.memorySnapshot()
        hasLoaded = true
    }

    func memory(_ id: UUID) throws -> MorieMemoryDTO {
        guard let item = entries.first(where: { $0.id == id }) else {
            throw StoreError.memoryUnavailable
        }
        return item
    }

    func evidence(for id: UUID) -> [MorieMemoryEvidenceDTO] {
        entries.first(where: { $0.id == id })?.evidence ?? []
    }

    func create(_ draft: MemoryDraft) async throws {
        entries = try await client.mutateMemory(.init(
            action: .create,
            kind: draft.kind.rawValue,
            name: draft.name,
            notes: draft.notes
        ))
        hasLoaded = true
    }

    func update(_ id: UUID, draft: MemoryDraft) async throws {
        entries = try await client.mutateMemory(.init(
            action: .update,
            id: id,
            kind: draft.kind.rawValue,
            name: draft.name,
            notes: draft.notes
        ))
        hasLoaded = true
    }

    func replace(_ id: UUID, with draft: MemoryDraft) async throws {
        entries = try await client.mutateMemory(.init(
            action: .replace,
            id: id,
            kind: draft.kind.rawValue,
            name: draft.name,
            notes: draft.notes
        ))
        hasLoaded = true
    }

    func archive(_ id: UUID) async throws {
        entries = try await client.mutateMemory(.init(action: .archive, id: id))
    }

    func restore(_ id: UUID) async throws {
        entries = try await client.mutateMemory(.init(action: .restore, id: id))
    }

    func delete(_ id: UUID) async throws {
        entries = try await client.mutateMemory(.init(action: .delete, id: id))
    }
}
