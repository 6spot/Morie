import Combine
import Foundation

@MainActor
final class AppCapabilityController: ObservableObject {
    @Published var needsSetup = false
    @Published var setupError: String?
    @Published var isBootstrapping = false
    @Published var speechBackend: SpeechRecognitionBackend?
}
