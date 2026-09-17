import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case checking
        case blocked
        case ready
        case recording
        case finalizing
        case failed(String)
    }

    private(set) var state: State = .checking
    private(set) var capabilityReport = CapabilityReport(issues: [])
    private(set) var transcript = ""
    private(set) var lastDeliveredText = ""
    private(set) var deliveryMethod: TextInjector.Method?

    private let capabilityGate = CapabilityGate()
    private let speechSession = AppleSpeechSession()
    private let injector = TextInjector()
    private var hotKey: GlobalHotKey?
    private var targetApp: FrontmostAppTarget?
    private var started = false

    var menuBarSymbol: String {
        switch state {
        case .recording: "waveform.circle.fill"
        case .blocked, .failed: "exclamationmark.circle"
        case .checking, .finalizing: "ellipsis.circle"
        case .ready: "waveform.circle"
        }
    }

    var stateLabel: String {
        switch state {
        case .checking: "Checking Private Mode capabilities…"
        case .blocked: "Private Mode unavailable"
        case .ready: "Ready · hold ⌃⌥Space to talk"
        case .recording: "Listening… release ⌃⌥Space to insert"
        case .finalizing: "Finalizing transcript…"
        case .failed(let message): "Error: \(message)"
        }
    }

    func start() async {
        guard !started else { return }
        started = true

        do {
            let hotKey = GlobalHotKey()
            try hotKey.register(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | optionKey),
                onPress: { [weak self] in self?.hotKeyPressed() },
                onRelease: { [weak self] in self?.hotKeyReleased() }
            )
            self.hotKey = hotKey
        } catch {
            state = .failed("Global shortcut registration failed: \(error.localizedDescription)")
            return
        }

        await recheckCapabilities()
    }

    func recheckCapabilities() async {
        guard state != .recording && state != .finalizing else { return }
        state = .checking
        let report = await capabilityGate.evaluate(locale: .current)
        capabilityReport = report
        state = report.isReady ? .ready : .blocked
    }

    func requestPermissions() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        await recheckCapabilities()
    }

    private func hotKeyPressed() {
        guard state == .ready else { return }
        targetApp = FrontmostAppTarget.capture(excluding: Bundle.main.bundleIdentifier)
        transcript = ""
        deliveryMethod = nil
        state = .recording

        Task {
            do {
                try await speechSession.start(locale: .current) { [weak self] text, _ in
                    Task { @MainActor in
                        self?.transcript = text
                    }
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func hotKeyReleased() {
        guard state == .recording else { return }
        state = .finalizing

        Task {
            do {
                let finalText = try await speechSession.stop()
                transcript = finalText

                guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state = .ready
                    return
                }

                targetApp?.restoreFocus()
                try await Task.sleep(for: .milliseconds(120))
                let method = try injector.insert(finalText)
                deliveryMethod = method
                lastDeliveredText = finalText
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
