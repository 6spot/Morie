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
    @Published var needsSetup = false
    @Published var setupError: String?
    @Published var isBootstrapping = false
    @Published var speechBackend: SpeechRecognitionBackend?

    var statusTitle: String {
        switch state {
        case .checking:
            "正在准备 Morie"
        case .blocked:
            "需要完成设置"
        case .ready:
            "可以开始录音"
        case .recording:
            "正在聆听…"
        case .stopping:
            "正在停止…"
        case .finalizing:
            "正在完成识别…"
        case .refining:
            "正在润色…"
        case .delivering:
            "正在输入…"
        case .failed:
            "输入失败"
        }
    }
}
