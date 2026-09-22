import Combine
import Foundation

struct SpeechBackendPresentation: Codable, Equatable, Sendable {
    let displayName: String
    let localeIdentifier: String
    let isFallback: Bool
}

@MainActor
final class AppCapabilityController: ObservableObject {
    @Published var needsSetup = false
    @Published var setupError: String?
    @Published var isBootstrapping = false
    @Published var speechBackend: SpeechBackendPresentation?
}
