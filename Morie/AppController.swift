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
    private var activeCaptureID: UUID?
    private var speechReadyCaptureID: UUID?
    private var captureStartTask: Task<Void, Never>?
    private var captureFinishTask: Task<Void, Never>?
    private var lastPresentedFailure: String?

    init() {
        // Morie is a menu-bar app. Capability checks and shortcut installation
        // must happen when the app launches, not only after the MenuBarExtra
        // content is opened for the first time.
        Task { @MainActor [weak self] in
            await self?.bootstrap()
        }
    }

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
        case .checking: "Checking device capabilities"
        case .blocked: "Required capability unavailable"
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
        await cancelActiveCapture(transitionToReady: false)
        hotkey?.invalidate()
        hotkey = nil

        state = .checking
        transcript = ""

        do {
            try await capabilityGate.requirePrivateMode()

            // Speech assets must be ready before the shortcut becomes active.
            // A model download must never start in the middle of a user's hold.
            try await speech.prepare(locale: .current)

            try installHotkeyIfNeeded()
            lastPresentedFailure = nil
            state = .ready
        } catch is CancellationError {
            // A newer bootstrap/cancellation path owns the visible state.
        } catch {
            hotkey?.invalidate()
            hotkey = nil

            let message = error.localizedDescription
            state = .blocked(message)
            presentFailure(title: "Morie can't start", message: message)
        }
    }

    private func installHotkeyIfNeeded() throws {
        guard hotkey == nil else { return }

        let hotkey = PushToTalkHotkey(
            onPress: { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyPress()
                }
            },
            onRelease: { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyRelease()
                }
            },
            onUnavailable: { [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor in
                    await self?.handleHotkeyUnavailable(message)
                }
            }
        )

        try hotkey.start()
        self.hotkey = hotkey
    }

    private func handleHotkeyPress() {
        guard activeCaptureID == nil else { return }

        switch state {
        case .ready, .failed:
            break
        default:
            return
        }

        lastPresentedFailure = nil

        let sessionID = UUID()
        activeCaptureID = sessionID
        speechReadyCaptureID = nil
        targetApplication = NSWorkspace.shared.frontmostApplication
        transcript = ""
        state = .recording

        captureStartTask = Task { @MainActor [weak self] in
            await self?.startCapture(sessionID: sessionID)
        }
    }

    private func handleHotkeyRelease() {
        guard let sessionID = activeCaptureID else { return }

        if speechReadyCaptureID == sessionID {
            guard captureFinishTask == nil else { return }

            captureFinishTask = Task { @MainActor [weak self] in
                await self?.finishCapture(sessionID: sessionID)
            }
        } else {
            // Release during asynchronous setup means the user's intentional
            // hold is already over. Cancel setup instead of starting a late,
            // orphaned microphone session after release.
            captureStartTask?.cancel()
        }
    }

    private func startCapture(sessionID: UUID) async {
        do {
            try await speech.start(
                sessionID: sessionID,
                locale: .current
            ) { [weak self] resultSessionID, text in
                Task { @MainActor in
                    guard self?.activeCaptureID == resultSessionID else { return }
                    self?.transcript = text
                }
            }

            try Task.checkCancellation()
            guard activeCaptureID == sessionID else {
                await speech.cancel(sessionID: sessionID)
                return
            }

            speechReadyCaptureID = sessionID
            captureStartTask = nil
        } catch is CancellationError {
            await speech.cancel(sessionID: sessionID)
            completeCancelledSession(sessionID)
        } catch {
            await speech.cancel(sessionID: sessionID)
            failSession(sessionID, error: error)
        }
    }

    private func finishCapture(sessionID: UUID) async {
        guard activeCaptureID == sessionID,
              speechReadyCaptureID == sessionID
        else {
            return
        }

        state = .delivering

        do {
            let finalText = try await speech.stop(sessionID: sessionID)
            try Task.checkCancellation()
            guard activeCaptureID == sessionID else { return }

            transcript = finalText

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completeSuccessfulSession(sessionID)
                return
            }

            try await injector.deliver(finalText, to: targetApplication)
            try Task.checkCancellation()
            completeSuccessfulSession(sessionID)
        } catch is CancellationError {
            await speech.cancel(sessionID: sessionID)
            completeCancelledSession(sessionID)
        } catch {
            await speech.cancel(sessionID: sessionID)
            failSession(sessionID, error: error)
        }
    }

    private func handleHotkeyUnavailable(_ message: String) async {
        await cancelActiveCapture(transitionToReady: false)
        state = .blocked(message)
        presentFailure(title: "Morie shortcut unavailable", message: message)
    }

    private func cancelActiveCapture(transitionToReady: Bool) async {
        guard let sessionID = activeCaptureID else {
            captureStartTask?.cancel()
            captureFinishTask?.cancel()
            captureStartTask = nil
            captureFinishTask = nil
            speechReadyCaptureID = nil
            targetApplication = nil
            return
        }

        let startTask = captureStartTask
        let finishTask = captureFinishTask
        startTask?.cancel()
        finishTask?.cancel()

        if let startTask {
            await startTask.value
        }
        if let finishTask {
            await finishTask.value
        }

        await speech.cancel(sessionID: sessionID)

        guard activeCaptureID == sessionID else { return }
        resetSessionIdentity()
        if transitionToReady {
            state = .ready
        }
    }

    private func completeSuccessfulSession(_ sessionID: UUID) {
        guard activeCaptureID == sessionID else { return }
        resetSessionIdentity()
        lastPresentedFailure = nil
        state = .ready
    }

    private func completeCancelledSession(_ sessionID: UUID) {
        guard activeCaptureID == sessionID else { return }
        resetSessionIdentity()
        state = .ready
    }

    private func failSession(_ sessionID: UUID, error: Error) {
        guard activeCaptureID == sessionID else { return }

        let message = error.localizedDescription
        resetSessionIdentity()
        state = .failed(message)
        presentFailure(title: "Morie input failed", message: message)
    }

    private func resetSessionIdentity() {
        activeCaptureID = nil
        speechReadyCaptureID = nil
        captureStartTask = nil
        captureFinishTask = nil
        targetApplication = nil
    }

    private func presentFailure(title: String, message: String) {
        guard lastPresentedFailure != message else { return }
        lastPresentedFailure = message

        // NSAlert is a native macOS surface. It remains visible even though
        // Morie runs as an LSUIElement menu-bar app, so launch/runtime failures
        // are never hidden behind an unopened menu extra.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
