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
        Diagnostics.record("App", "Morie controller initialized; launch bootstrap scheduled")
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
        Diagnostics.record("App", "Bootstrap started")
        await cancelActiveCapture(transitionToReady: false)
        hotkey?.invalidate()
        hotkey = nil

        state = .checking
        transcript = ""

        do {
            try await capabilityGate.requirePrivateMode()
            Diagnostics.record("App", "Capability gate passed; preparing Speech assets")

            try await speech.prepare(locale: .current)
            Diagnostics.record("App", "Speech assets ready; installing global hotkey")

            try installHotkeyIfNeeded()
            lastPresentedFailure = nil
            state = .ready
            Diagnostics.record("App", "Bootstrap complete; Morie is Ready")
        } catch is CancellationError {
            Diagnostics.record("App", "Bootstrap cancelled", level: .warning)
        } catch {
            hotkey?.invalidate()
            hotkey = nil

            let message = error.localizedDescription
            state = .blocked(message)
            Diagnostics.record("App", "Bootstrap blocked: \(message)", level: .error)
            presentFailure(title: "Morie can't start", message: message)
        }
    }

    private func installHotkeyIfNeeded() throws {
        guard hotkey == nil else {
            Diagnostics.record("Hotkey", "Controller already owns a hotkey instance")
            return
        }

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
        Diagnostics.record("Hotkey", "Controller installed Control+Space hotkey")
    }

    private func handleHotkeyPress() {
        guard activeCaptureID == nil else {
            Diagnostics.record("Session", "Hotkey press ignored because a capture is already active", level: .warning)
            return
        }

        switch state {
        case .ready, .failed:
            break
        default:
            Diagnostics.record("Session", "Hotkey press ignored while state=\(String(describing: state))", level: .warning)
            return
        }

        lastPresentedFailure = nil

        let sessionID = UUID()
        activeCaptureID = sessionID
        speechReadyCaptureID = nil
        targetApplication = NSWorkspace.shared.frontmostApplication
        transcript = ""
        state = .recording

        let targetName = targetApplication?.localizedName ?? "unknown"
        let targetBundle = targetApplication?.bundleIdentifier ?? "unknown"
        Diagnostics.record(
            "Session",
            "Capture \(label(sessionID)) started; target=\(targetName) (\(targetBundle))"
        )

        captureStartTask = Task { @MainActor [weak self] in
            await self?.startCapture(sessionID: sessionID)
        }
    }

    private func handleHotkeyRelease() {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record("Session", "Hotkey release received with no active capture", level: .warning)
            return
        }

        Diagnostics.record("Session", "Capture \(label(sessionID)) release received")

        if speechReadyCaptureID == sessionID {
            guard captureFinishTask == nil else {
                Diagnostics.record("Session", "Finish already running for \(label(sessionID))", level: .warning)
                return
            }

            captureFinishTask = Task { @MainActor [weak self] in
                await self?.finishCapture(sessionID: sessionID)
            }
        } else {
            Diagnostics.record(
                "Session",
                "Capture \(label(sessionID)) released before Speech start completed; cancelling setup",
                level: .warning
            )
            captureStartTask?.cancel()
        }
    }

    private func startCapture(sessionID: UUID) async {
        Diagnostics.record("Speech", "Starting Speech session \(label(sessionID))")

        do {
            try await speech.start(
                sessionID: sessionID,
                locale: .current
            ) { [weak self] resultSessionID, text in
                Task { @MainActor in
                    guard self?.activeCaptureID == resultSessionID else {
                        Diagnostics.record("Speech", "Ignored stale transcript for \(String(resultSessionID.uuidString.prefix(8)))", level: .warning)
                        return
                    }

                    self?.transcript = text
                    Diagnostics.record(
                        "Speech",
                        "Transcript update for \(String(resultSessionID.uuidString.prefix(8))); characters=\(text.count)"
                    )
                }
            }

            try Task.checkCancellation()
            guard activeCaptureID == sessionID else {
                Diagnostics.record("Speech", "Speech started after session ownership changed; cancelling \(label(sessionID))", level: .warning)
                await speech.cancel(sessionID: sessionID)
                return
            }

            speechReadyCaptureID = sessionID
            captureStartTask = nil
            Diagnostics.record("Speech", "Speech session \(label(sessionID)) is recording")
        } catch is CancellationError {
            Diagnostics.record("Speech", "Speech start cancelled for \(label(sessionID))", level: .warning)
            await speech.cancel(sessionID: sessionID)
            completeCancelledSession(sessionID)
        } catch {
            Diagnostics.record("Speech", "Speech start failed for \(label(sessionID)): \(error.localizedDescription)", level: .error)
            await speech.cancel(sessionID: sessionID)
            failSession(sessionID, error: error)
        }
    }

    private func finishCapture(sessionID: UUID) async {
        guard activeCaptureID == sessionID,
              speechReadyCaptureID == sessionID
        else {
            Diagnostics.record("Session", "Finish ignored because \(label(sessionID)) is no longer active/ready", level: .warning)
            return
        }

        state = .delivering
        Diagnostics.record("Speech", "Finalizing Speech session \(label(sessionID))")

        do {
            let finalText = try await speech.stop(sessionID: sessionID)
            try Task.checkCancellation()
            guard activeCaptureID == sessionID else {
                Diagnostics.record("Session", "Final result arrived after session ownership changed", level: .warning)
                return
            }

            transcript = finalText
            Diagnostics.record("Speech", "Final transcript ready; characters=\(finalText.count)")

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Diagnostics.record("Delivery", "Final transcript is empty; nothing to inject", level: .warning)
                completeSuccessfulSession(sessionID)
                return
            }

            let targetName = targetApplication?.localizedName ?? "unknown"
            let targetBundle = targetApplication?.bundleIdentifier ?? "unknown"
            Diagnostics.record("Delivery", "Injecting \(finalText.count) characters into \(targetName) (\(targetBundle))")

            try await injector.deliver(finalText, to: targetApplication)
            try Task.checkCancellation()
            Diagnostics.record("Delivery", "Injection completed for \(label(sessionID))")
            completeSuccessfulSession(sessionID)
        } catch is CancellationError {
            Diagnostics.record("Session", "Finish cancelled for \(label(sessionID))", level: .warning)
            await speech.cancel(sessionID: sessionID)
            completeCancelledSession(sessionID)
        } catch {
            Diagnostics.record("Session", "Capture \(label(sessionID)) failed: \(error.localizedDescription)", level: .error)
            await speech.cancel(sessionID: sessionID)
            failSession(sessionID, error: error)
        }
    }

    private func handleHotkeyUnavailable(_ message: String) async {
        Diagnostics.record("Hotkey", "Global shortcut became unavailable: \(message)", level: .error)
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

        Diagnostics.record("Session", "Cancelling active capture \(label(sessionID))")

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
        Diagnostics.record("Session", "Capture \(label(sessionID)) completed successfully")
        resetSessionIdentity()
        lastPresentedFailure = nil
        state = .ready
    }

    private func completeCancelledSession(_ sessionID: UUID) {
        guard activeCaptureID == sessionID else { return }
        Diagnostics.record("Session", "Capture \(label(sessionID)) cancelled", level: .warning)
        resetSessionIdentity()
        state = .ready
    }

    private func failSession(_ sessionID: UUID, error: Error) {
        guard activeCaptureID == sessionID else { return }

        let message = error.localizedDescription
        Diagnostics.record("Session", "Capture \(label(sessionID)) failed: \(message)", level: .error)
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
        Diagnostics.record("UI", "Presenting alert: \(title) — \(message)", level: .warning)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func label(_ sessionID: UUID) -> String {
        String(sessionID.uuidString.prefix(8))
    }
}
