import AppKit
import SwiftUI

@MainActor
final class CaptureHUDController {
    private let model = CaptureHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    var onCancel: (() -> Void)? {
        didSet { model.onCancel = onCancel }
    }

    var onConfirm: (() -> Void)? {
        didSet { model.onConfirm = onConfirm }
    }

    func showRecording() {
        hideTask?.cancel()
        hideTask = nil

        model.phase = .recording
        model.resetLevels()
        showPanel()
        Diagnostics.record("HUD", "Capture HUD shown in recording state")
    }

    func updateAudioLevel(_ level: Double) {
        guard model.phase == .recording else { return }
        model.appendLevel(level)
    }

    func showProcessing() {
        hideTask?.cancel()
        hideTask = nil

        model.phase = .processing
        showPanel()
        Diagnostics.record("HUD", "Capture HUD entered processing state")
    }

    func showSuccess() {
        hideTask?.cancel()
        model.phase = .success
        showPanel()
        Diagnostics.record("HUD", "Capture HUD showing success")

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showFailure() {
        hideTask?.cancel()
        model.phase = .failure
        showPanel()
        Diagnostics.record("HUD", "Capture HUD showing failure", level: .warning)

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        model.resetLevels()
        Diagnostics.record("HUD", "Capture HUD hidden")
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 170, height: 50)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CaptureHUDView(model: model))

        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.minY + 58
        )

        panel.setFrameOrigin(origin)
    }
}

@MainActor
private final class CaptureHUDModel: ObservableObject {
    enum Phase: Equatable {
        case recording
        case processing
        case success
        case failure
    }

    @Published var phase: Phase = .recording
    @Published private(set) var levels = Array(repeating: 0.03, count: 11)

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    func appendLevel(_ level: Double) {
        let value = min(max(level, 0), 1)
        levels.removeFirst()
        levels.append(value)
    }

    func resetLevels() {
        levels = Array(repeating: 0.03, count: levels.count)
    }

    func cancel() {
        Diagnostics.record("HUD", "Cancel button pressed")
        onCancel?()
    }

    func confirm() {
        Diagnostics.record("HUD", "Confirm button pressed")
        onConfirm?()
    }
}

@MainActor
private struct CaptureHUDView: View {
    @ObservedObject var model: CaptureHUDModel

    var body: some View {
        Group {
            switch model.phase {
            case .recording:
                HStack(spacing: 8) {
                    hudButton(
                        systemImage: "xmark",
                        foreground: .white,
                        background: Color(nsColor: .darkGray),
                        action: model.cancel
                    )

                    AudioLevelBars(levels: model.levels)
                        .frame(width: 70, height: 26)

                    hudButton(
                        systemImage: "checkmark",
                        foreground: .black,
                        background: .white,
                        action: model.confirm
                    )
                }

            case .processing:
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(nsColor: .darkGray))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }

                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Spacer(minLength: 0)

                    Circle()
                        .fill(.white)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                }

            case .success:
                HStack {
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }

            case .failure:
                HStack {
                    Spacer()
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .padding(6)
        .frame(width: 170, height: 50)
        .background(.black, in: Capsule())
    }

    private func hudButton(
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 34, height: 34)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct AudioLevelBars: View {
    let levels: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: 4 + 22 * level)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.linear(duration: 0.07), value: levels)
    }
}
