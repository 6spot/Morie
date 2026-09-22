import AppKit
import Foundation

@MainActor
final class MorieRuntimeStatusItem: NSObject {
    private let controller: MorieRuntimeController
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    init(controller: MorieRuntimeController) {
        self.controller = controller
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        item.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Morie"
        )
        item.button?.toolTip = "Morie"
        item.menu = makeMenu()
        statusItem = item

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        statusItem?.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(
            title: controller.statusTitle,
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let open = NSMenuItem(
            title: "打开 Morie",
            action: #selector(openMorie),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        let capture = NSMenuItem(
            title: "开始录音并保存到历史记录",
            action: #selector(startCaptureOnly),
            keyEquivalent: ""
        )
        capture.target = self
        capture.isEnabled = controller.canStartCapture
        menu.addItem(capture)

        return menu
    }

    @objc private func openMorie() {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        )
    }

    @objc private func startCaptureOnly() {
        controller.startCaptureOnly()
    }
}
