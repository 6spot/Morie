import AppKit
import Foundation

@MainActor
final class AppController: ObservableObject {
    enum ControllerError: LocalizedError {
        case persistenceUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .persistenceUnavailable(let reason):
                "Capture storage is unavailable: \(reason)"
            }
        }
    }

    enum State: Equatable {
        case checking
        case blocked(String)
        case ready
        case recording
        case finalizing
        case delivering
        case failed(String)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var transcript = ""
    @Published private(set) var captureShortcut: CaptureShortcut
    @Published private(set) var recoverySettingsURL: URL?

    private let capabilityGate = CapabilityGate()
    private let speech = SpeechPipeline()
    private let injector = TextInjector()
    private let hud = CaptureHUDController()
    private let captureStore: CaptureStore?
    private let persistenceError: Error?
    private let speechLocale = Locale(identifier: "zh-CN")

    private var hotkey: PushToTalkHotkey?
    private var targetApplication: NSRunningApplication?
    private var targetWindowNumber: CGWindowID?
    private var activeCaptureID: UUID?
    private var speechReadyCaptureID: UUID?
    private var finishRequestedCaptureID: UUID?
    private var captureStartTask: Task<Void, Never>?
    private var captureFinishTask: Task<Void, Never>?
    private var lastPresentedFailure: String?

    init(captureStore: CaptureStore?, persistenceError: Error? = nil) {
        self.captureStore = captureStore
        self.persistenceError = persistenceError
        let savedShortcut = UserDefaults.standard.string(forKey: CaptureShortcut.defaultsKey)
            .flatMap(CaptureShortcut.init(rawValue:))
        captureShortcut = savedShortcut ?? CaptureShortcut.defaultValue

        hud.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelCaptureFromUser(source: "HUD")
            }
        }
        hud.onConfirm = { [weak self] in
            Task { @MainActor in
                self?.requestFinishActiveCapture(source: "HUD")
            }
        }

        Diagnostics.record("App", "Morie controller initialized; launch bootstrap scheduled")
        Task { @MainActor [weak self] in
            await self?.bootstrap()
        }
    }

    var statusTitle: String {
        switch state {
        case .checking: "Checking device capabilities"
        case .blocked: "Required capability unavailable"
        case .ready: "Ready"
        case .recording: "Listening…"
        case .finalizing: "Finalizing…"
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
        recoverySettingsURL = nil

        do {
            if let persistenceError {
                throw ControllerError.persistenceUnavailable(persistenceError.localizedDescription)
            }
            guard captureStore != nil else {
                throw ControllerError.persistenceUnavailable("Capture store was not initialized.")
            }

            try await capabilityGate.requirePrivateMode()
            Diagnostics.record(
                "App",
                "Capability gate passed; preparing Speech assets for locale \(speechLocale.identifier)"
            )

            try await speech.prepare(locale: speechLocale)
            Diagnostics.record("App", "Speech assets ready; installing global hotkey")

            try installHotkeyIfNeeded()
            lastPresentedFailure = nil
            recoverySettingsURL = nil
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
            if let gateError = error as? CapabilityGate.GateError {
                recoverySettingsURL = gateError.settingsURL
                if case .accessibilityDenied = gateError {
                    Diagnostics.record(
                        "UI",
                        "Accessibility failure remains visible in app status; duplicate Morie alert suppressed",
                        level: .warning
                    )
                } else {
                    presentCapabilityFailure(gateError)
                }
            } else {
                presentFailure(title: "Morie can't start", message: message)
            }
        }
    }

    func openRecoverySettings() {
        guard let recoverySettingsURL else { return }
        Diagnostics.record("Permission", "Opening recovery System Settings from menu")
        NSWorkspace.shared.open(recoverySettingsURL)
    }

    private func installHotkeyIfNeeded() throws {
        guard hotkey == nil else {
            Diagnostics.record("Hotkey", "Controller already owns a hotkey instance")
            return
        }

        let hotkey = PushToTalkHotkey(
            shortcut: captureShortcut,
            onToggle: { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyToggle()
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    await self?.cancelCaptureFromUser(source: "Escape")
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
        Diagnostics.record("Hotkey", "Controller installed \(captureShortcut.logName) toggle hotkey")
    }

    func setCaptureShortcut(_ shortcut: CaptureShortcut) {
        guard shortcut != captureShortcut else { return }
        guard activeCaptureID == nil else {
            Diagnostics.record("Hotkey", "Shortcut change ignored during an active capture", level: .warning)
            return
        }

        captureShortcut = shortcut
        UserDefaults.standard.set(shortcut.rawValue, forKey: CaptureShortcut.defaultsKey)
        Diagnostics.record("Hotkey", "Shortcut preference changed to \(shortcut.logName)")

        hotkey?.invalidate()
        hotkey = nil
        do {
            try installHotkeyIfNeeded()
        } catch {
            Task { @MainActor [weak self] in
                await self?.handleHotkeyUnavailable(error.localizedDescription)
            }
        }
    }

    private func handleHotkeyToggle() {
        if activeCaptureID != nil {
            requestFinishActiveCapture(source: captureShortcut.logName)
            return
        }

        switch state {
        case .ready, .failed:
            startNewCapture()
        default:
            Diagnostics.record("Session", "Toggle ignored while state=\(String(describing: state))", level: .warning)
        }
    }

    private func startNewCapture() {
        guard activeCaptureID == nil else { return }

        lastPresentedFailure = nil

        let sessionID = UUID()
        targetApplication = NSWorkspace.shared.frontmostApplication
        targetWindowNumber = TextInjector.frontmostWindowNumber(for: targetApplication)

        do {
            try captureStore?.beginVoiceCapture(
                id: sessionID,
                applicationName: targetApplication?.localizedName,
                bundleIdentifier: targetApplication?.bundleIdentifier,
                windowNumber: targetWindowNumber
            )
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            Diagnostics.record("CaptureStore", "Could not create Capture \(label(sessionID)): \(message)", level: .error)
            presentFailure(title: "Morie couldn't save this capture", message: message)
            return
        }

        activeCaptureID = sessionID
        speechReadyCaptureID = nil
        finishRequestedCaptureID = nil
        transcript = ""
        state = .recording

        hotkey?.setCancellationEnabled(true)
        hud.showRecording()

        let targetName = targetApplication?.localizedName ?? "unknown"
        let targetBundle = targetApplication?.bundleIdentifier ?? "unknown"
        Diagnostics.record(
            "Session",
            "Capture \(label(sessionID)) started; target=\(targetName) (\(targetBundle)); window=\(targetWindowNumber.map(String.init) ?? "unknown"); locale=\(speechLocale.identifier)"
        )

        captureStartTask = Task { @MainActor [weak self] in
            await self?.startCapture(sessionID: sessionID)
        }
    }

    private func requestFinishActiveCapture(source: String) {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record("Session", "Finish requested from \(source) with no active capture", level: .warning)
            return
        }

        guard finishRequestedCaptureID != sessionID, captureFinishTask == nil else {
            Diagnostics.record("Session", "Duplicate finish request ignored for \(label(sessionID))", level: .warning)
            return
        }

        finishRequestedCaptureID = sessionID
        state = .finalizing
        hotkey?.setCancellationEnabled(false)
        hud.showProcessing()
        Diagnostics.record("Session", "Finish requested for \(label(sessionID)) from \(source)")

        if speechReadyCaptureID == sessionID {
            beginFinish(sessionID: sessionID)
        } else {
            Diagnostics.record("Session", "Finish for \(label(sessionID)) is pending Speech startup")
        }
    }

    private func beginFinish(sessionID: UUID) {
        guard activeCaptureID == sessionID,
              speechReadyCaptureID == sessionID,
              captureFinishTask == nil
        else {
            return
        }

        captureFinishTask = Task { @MainActor [weak self] in
            await self?.finishCapture(sessionID: sessionID)
        }
    }

    private func startCapture(sessionID: UUID) async {
        Diagnostics.record("Speech", "Starting Speech session \(label(sessionID))")

        do {
            try await speech.start(
                sessionID: sessionID,
                locale: speechLocale,
                onTranscript: { [weak self] resultSessionID, text in
                    Task { @MainActor in
                        guard self?.activeCaptureID == resultSessionID else {
                            Diagnostics.record("Speech", "Ignored stale transcript for \(String(resultSessionID.uuidString.prefix(8)))", level: .warning)
                            return
                        }

                        self?.transcript = text
                        do {
                            try self?.captureStore?.updateRecognizedText(text, for: resultSessionID)
                        } catch {
                            Diagnostics.record(
                                "CaptureStore",
                                "Progressive save failed for \(String(resultSessionID.uuidString.prefix(8))): \(error.localizedDescription)",
                                level: .error
                            )
                        }
                        Diagnostics.record(
                            "Speech",
                            "Transcript update for \(String(resultSessionID.uuidString.prefix(8))); characters=\(text.count)"
                        )
                    }
                },
                onAudioLevel: { [weak self] resultSessionID, level in
                    Task { @MainActor in
                        guard self?.activeCaptureID == resultSessionID,
                              self?.state == .recording
                        else { return }

                        self?.hud.updateAudioLevel(level)
                    }
                }
            )

            try Task.checkCancellation()
            guard activeCaptureID == sessionID else {
                Diagnostics.record("Speech", "Speech started after session ownership changed; cancelling \(label(sessionID))", level: .warning)
                await speech.cancel(sessionID: sessionID)
                return
            }

            speechReadyCaptureID = sessionID
            captureStartTask = nil
            Diagnostics.record("Speech", "Speech session \(label(sessionID)) is recording")

            if finishRequestedCaptureID == sessionID {
                Diagnostics.record("Session", "Applying pending finish request for \(label(sessionID))")
                beginFinish(sessionID: sessionID)
            }
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

        state = .finalizing
        hud.showProcessing()
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
            try captureStore?.completeRecognition(finalText, for: sessionID)

            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Diagnostics.record("Delivery", "Final transcript is empty; nothing to inject", level: .warning)
                try captureStore?.markDelivered(sessionID)
                completeSuccessfulSession(sessionID)
                return
            }

            state = .delivering
            hud.showProcessing()

            let targetName = targetApplication?.localizedName ?? "unknown"
            let targetBundle = targetApplication?.bundleIdentifier ?? "unknown"
            Diagnostics.record("Delivery", "Injecting \(finalText.count) characters into \(targetName) (\(targetBundle))")

            try await injector.deliver(
                finalText,
                to: targetApplication,
                originalWindowNumber: targetWindowNumber
            )
            try Task.checkCancellation()
            Diagnostics.record("Delivery", "Injection completed for \(label(sessionID))")
            try captureStore?.markDelivered(sessionID)
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

    private func cancelCaptureFromUser(source: String) async {
        guard let sessionID = activeCaptureID else {
            Diagnostics.record("Session", "Cancel requested from \(source) with no active capture", level: .warning)
            return
        }

        guard state == .recording else {
            Diagnostics.record("Session", "Cancel from \(source) ignored while state=\(String(describing: state))", level: .warning)
            return
        }

        Diagnostics.record("Session", "Capture \(label(sessionID)) cancelled by \(source)", level: .warning)
        do {
            try captureStore?.cancel(sessionID)
        } catch {
            Diagnostics.record("CaptureStore", "Cancel cleanup failed: \(error.localizedDescription)", level: .error)
        }
        hotkey?.setCancellationEnabled(false)
        hud.hide()
        await cancelActiveCapture(transitionToReady: true)
    }

    private func handleHotkeyUnavailable(_ message: String) async {
        Diagnostics.record("Hotkey", "Global shortcut became unavailable: \(message)", level: .error)
        await cancelActiveCapture(transitionToReady: false)
        state = .blocked(message)
        hud.showFailure()
        Diagnostics.record(
            "UI",
            "Hotkey failure reported without a modal alert so keyboard and pointer interaction remain available",
            level: .warning
        )
    }

    private func cancelActiveCapture(transitionToReady: Bool) async {
        hotkey?.setCancellationEnabled(false)
        hud.hide()

        guard let sessionID = activeCaptureID else {
            captureStartTask?.cancel()
            captureFinishTask?.cancel()
            captureStartTask = nil
            captureFinishTask = nil
            speechReadyCaptureID = nil
            finishRequestedCaptureID = nil
            targetApplication = nil
            targetWindowNumber = nil
            return
        }

        Diagnostics.record("Session", "Cancelling active capture \(label(sessionID))")

        do {
            try captureStore?.cancel(sessionID)
        } catch {
            Diagnostics.record("CaptureStore", "Active Capture cleanup failed: \(error.localizedDescription)", level: .error)
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
        Diagnostics.record("Session", "Capture \(label(sessionID)) completed successfully")
        hotkey?.setCancellationEnabled(false)
        resetSessionIdentity()
        lastPresentedFailure = nil
        state = .ready
        hud.showSuccess()
    }

    private func completeCancelledSession(_ sessionID: UUID) {
        guard activeCaptureID == sessionID else { return }
        Diagnostics.record("Session", "Capture \(label(sessionID)) cancelled", level: .warning)
        hotkey?.setCancellationEnabled(false)
        resetSessionIdentity()
        state = .ready
        hud.hide()
    }

    private func failSession(_ sessionID: UUID, error: Error) {
        guard activeCaptureID == sessionID else { return }

        let message = error.localizedDescription
        let preservedOnClipboard = error is TextInjector.InjectionError
        do {
            if preservedOnClipboard {
                try captureStore?.markDeliveryFailed(sessionID, error: message)
            } else {
                try captureStore?.markFailed(sessionID, error: message)
            }
        } catch {
            Diagnostics.record("CaptureStore", "Failure state save failed: \(error.localizedDescription)", level: .error)
        }
        Diagnostics.record("Session", "Capture \(label(sessionID)) failed: \(message)", level: .error)
        hotkey?.setCancellationEnabled(false)
        resetSessionIdentity()
        state = .failed(message)

        if preservedOnClipboard {
            hud.showClipboardFallback()
            Diagnostics.record(
                "UI",
                "Delivery fallback reported in HUD; modal alert suppressed because transcript is preserved",
                level: .warning
            )
        } else {
            hud.showFailure()
            presentFailure(title: "Morie input failed", message: message)
        }
    }

    private func resetSessionIdentity() {
        activeCaptureID = nil
        speechReadyCaptureID = nil
        finishRequestedCaptureID = nil
        captureStartTask = nil
        captureFinishTask = nil
        targetApplication = nil
        targetWindowNumber = nil
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

    private func presentCapabilityFailure(_ error: CapabilityGate.GateError) {
        let message = error.localizedDescription
        guard lastPresentedFailure != message else { return }
        lastPresentedFailure = message
        Diagnostics.record("UI", "Presenting capability alert: \(message)", level: .warning)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Morie can't start"
        alert.informativeText = message

        if let settingsURL = error.settingsURL {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")

            NSApplication.shared.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                Diagnostics.record("Permission", "Opening System Settings for \(String(describing: error))")
                NSWorkspace.shared.open(settingsURL)
            }
        } else {
            alert.addButton(withTitle: "OK")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func label(_ sessionID: UUID) -> String {
        String(sessionID.uuidString.prefix(8))
    }
}
