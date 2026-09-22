import Combine
import Foundation

@MainActor
final class MorieRuntimeCapabilityController: ObservableObject {
    @Published var needsSetup = false
    @Published var setupError: String?
    @Published var isBootstrapping = false
    @Published var speechBackend: SpeechRecognitionBackend?
}
