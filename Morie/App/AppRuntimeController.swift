import Combine
import Foundation

@MainActor
final class AppRuntimeController: ObservableObject {
    enum State: Equatable {
        case checking
        case blocked(String)
        case ready
        case recording
        case stopping
        case finalizing
        case refining
        case delivering
        case failed(String)
    }

    @Published var state: State = .checking
    @Published var transcript = ""
}
