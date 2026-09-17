import AppKit
import Foundation

@MainActor
final class AppController: ObservableObject {
    enum State: Equatable {
        case checking
        case blocked(String)
        case ready
        case recording
        case delivering
        case failed(String)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var transcript = ""

    private let capabilityGate = CapabilityGate()
    private let speech = SpeechPipeline()
    private let injector = TextInjector()
    private var hotkey: PushToTalkHotkey?
    private var targetApplication: NSRunningApplication?

    var statusSymbol: String {
        switch state {
        case .checking: "ellipsis.circle"
        case .blocked: "exclamationmark.triangle"
        case .ready: "waveform"
        case .recording: "waveform.circle.fill"
        case .delivering: "arrow.right.circle"
        case .failed: "xmark.circle"
        }
    }

    var statusTitle: String {
        switch state {
        case .checking: "Checking Private Mode"
        case .blocked: "Private Mode unavailable"
        case .ready: "Ready"
        case .recording: "Listening…"
        case .delivering: "Delivering…"
        case .failed: "Input failed"
        }
    }

    var statusDetail: String? {
        switch state {
        case .blocked(let reason), .failed(let reason): reason
        default: nil
        }
    }

    func bootstrap() async {
        state = .checking
        transcript = ""

        do {
            try await capabilityGate.requirePrivateMode()
            installHotkeyIfNeeded()
            state = .ready
        } catch {
            hotkey?.invalidate()
            hotkey = nil
            state = .blocked(error.localizedDescription)
        }
    }

    private func installHotkeyIfNeeded() {
        guard hotkey == nil else { return }

        hotkey = PushToTalkHotkey(
            onPress: { [weak self] in
                Task { @MainActor in await self?.beginCapture() }
            },
            onRelease: { [weak self] in
                Task { @MainActor in await self?.finishCapture() }
            }
        )
    }

    private func beginCapture() async {
        guard state == .ready else { return }

        targetApplication = NSWorkspace.shared.frontmostApplication
        transcript = ""
        state = .recording

        do {
            try await speech.start(locale: .current) { [weak self] text in
                Task { @MainActor in self?.transcript = text }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishCapture() async {
        guard state == .recording else { return }
        state = .delivering

        do {
            let finalText = try await speech.stop()
            transcript = finalText

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .ready
                return
            }

            try await injector.deliver(finalText, to: targetApplication)
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
