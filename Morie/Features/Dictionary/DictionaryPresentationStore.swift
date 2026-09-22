import Combine
import Foundation

@MainActor
final class DictionaryPresentationStore: ObservableObject {
    @Published private(set) var entries: [MorieDictionaryEntryDTO] = []
    private let client: MorieRuntimeClient
    private var hasLoaded = false

    init(client: MorieRuntimeClient) {
        self.client = client
    }

    var displayEntries: [MorieDictionaryEntryDTO] { entries }

    func loadIfNeeded() async throws {
        guard !hasLoaded else { return }
        try await load()
    }

    func load() async throws {
        entries = try await client.dictionarySnapshot()
        hasLoaded = true
    }

    func create(_ name: String) async throws {
        entries = try await client.mutateDictionary(.init(
            action: .create,
            name: name
        ))
        hasLoaded = true
    }

    func update(_ id: UUID, name: String) async throws {
        entries = try await client.mutateDictionary(.init(
            action: .update,
            id: id,
            name: name
        ))
        hasLoaded = true
    }

    func delete(_ id: UUID) async throws {
        entries = try await client.mutateDictionary(.init(
            action: .delete,
            id: id
        ))
        hasLoaded = true
    }
}
