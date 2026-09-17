import AppKit
import SwiftUI

@MainActor
final class CaptureHUDController {
    private let model = CaptureHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private enum Layout {
        static let capsuleWidth: CGFloat = 180
        static let capsuleHeight: CGFloat = 24
        static let shadowInset: CGFloat = 8
        static let bottomOffset: CGFloat = 48

        static var panelSize: NSSize {
            NSSize(
                width: capsuleWidth + shadowInset * 2,
                height: capsuleHeight + shadowInset * 2
            )
        }
    }

    var onCancel: (() -> Void)? {
        didSet { model.onCancel = onCancel }
    }

    var onConfirm: (() -> Void)? {
        didSet { model.onConfirm = onConfirm }
    }

    func showRecording() {
        hideTask?.cancel()
        hideTask = nil

        model.beginRecording()
        showPanel()
        Diagnostics.record("HUD", "Compact capture HUD shown in recording state")
    }

    func updateAudioLevel(_ level: Double) {
        guard model.phase == .recording else { return }
        model.updateAudioLevel(level)
    }

    func showProcessing() {
        hideTask?.cancel()
        hideTask = nil

        model.phase = .processing
        showPanel()
        Diagnostics.record("HUD", "Compact capture HUD entered processing state")
    }

    func showSuccess() {
        hideTask?.cancel()
        model.phase = .success
        showPanel()
        Diagnostics.record("HUD", "Compact capture HUD showing success")

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showFailure() {
        hideTask?.cancel()
        model.phase = .failure
        showPanel()
        Diagnostics.record("HUD", "Compact capture HUD showing failure", level: .warning)

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
        model.resetAudioLevel()
        Diagnostics.record("HUD", "Capture HUD hidden")
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let size = Layout.panelSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        let hostingView = NSHostingView(rootView: CaptureHUDView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

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
            x: (visibleFrame.midX - frame.width / 2).rounded(),
            y: (visibleFrame.minY + Layout.bottomOffset - Layout.shadowInset).rounded()
        )

        panel.setFrameOrigin(origin)
    }
}

private final class CaptureAudioLevelMeter {
    var current: Double = 0
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
    @Published private(set) var recordingGeneration = UUID()

    let audioLevel = CaptureAudioLevelMeter()

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    func beginRecording() {
        audioLevel.current = 0
        recordingGeneration = UUID()
        phase = .recording
    }

    func updateAudioLevel(_ level: Double) {
        audioLevel.current = min(max(level, 0), 1)
    }

    func resetAudioLevel() {
        audioLevel.current = 0
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

    private enum Layout {
        static let capsuleWidth: CGFloat = 180
        static let capsuleHeight: CGFloat = 24
        static let shadowInset: CGFloat = 8
        static let controlLaneWidth: CGFloat = 32
        static let controlVisualSize: CGFloat = 15
        static let waveformBarWidth: CGFloat = 2
        static let waveformMinHeight: CGFloat = 2
        static let waveformMaxHeight: CGFloat = 18
    }

    private let background = Color(
        red: 17.0 / 255.0,
        green: 18.0 / 255.0,
        blue: 20.0 / 255.0
    )
    private let border = Color(
        red: 38.0 / 255.0,
        green: 39.0 / 255.0,
        blue: 41.0 / 255.0
    )

    var body: some View {
        phaseContent
            .frame(width: Layout.capsuleWidth, height: Layout.capsuleHeight)
            .background(background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(border, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
            .padding(Layout.shadowInset)
            .frame(
                width: Layout.capsuleWidth + Layout.shadowInset * 2,
                height: Layout.capsuleHeight + Layout.shadowInset * 2
            )
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .recording:
            HStack(spacing: 0) {
                compactButton(
                    systemImage: "xmark",
                    foreground: .white,
                    background: Color(red: 51.0 / 255.0, green: 51.0 / 255.0, blue: 51.0 / 255.0),
                    accessibilityLabel: "取消录音",
                    action: model.cancel
                )
                .frame(width: Layout.controlLaneWidth, height: Layout.capsuleHeight)

                CompactWaveform(
                    meter: model.audioLevel,
                    barWidth: Layout.waveformBarWidth,
                    minHeight: Layout.waveformMinHeight,
                    maxHeight: Layout.waveformMaxHeight
                )
                .id(model.recordingGeneration)
                .frame(maxWidth: .infinity, maxHeight: Layout.capsuleHeight)

                compactButton(
                    systemImage: "checkmark",
                    foreground: background,
                    background: Color(red: 251.0 / 255.0, green: 251.0 / 255.0, blue: 251.0 / 255.0),
                    accessibilityLabel: "完成录音",
                    action: model.confirm
                )
                .frame(width: Layout.controlLaneWidth, height: Layout.capsuleHeight)
            }

        case .processing:
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failure:
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func compactButton(
        systemImage: String,
        foreground: Color,
        background: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(background)
                .frame(width: Layout.controlVisualSize, height: Layout.controlVisualSize)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(foreground)
                }
                .frame(width: Layout.controlLaneWidth, height: Layout.capsuleHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CompactWaveSample {
    let height: CGFloat
    let isActive: Bool
}

@MainActor
private final class CompactWaveHistory {
    var samples: [CompactWaveSample] = []
    var lastSampleTime: TimeInterval = 0

    private let sampleInterval: TimeInterval = 0.085
    private let maxSamples = 64

    func update(
        currentTime: TimeInterval,
        level: Double,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        if lastSampleTime == 0 {
            lastSampleTime = currentTime
        }

        let elapsed = currentTime - lastSampleTime
        if elapsed >= sampleInterval {
            let steps = Int(elapsed / sampleInterval)
            let normalized = max(0, min(1, CGFloat(level)))
            let silenceThreshold: CGFloat = 0.025

            for _ in 0..<min(steps, 10) {
                let sample: CompactWaveSample
                if normalized <= silenceThreshold {
                    sample = CompactWaveSample(height: minHeight, isActive: false)
                } else {
                    let effective = (normalized - silenceThreshold) / (1 - silenceThreshold)
                    // Audio-derived visual gain only: preserve the real level shape while
                    // expanding normal speaking dynamics so the compact meter is legible.
                    let visualEnergy = min(1, pow(effective, 0.55) * 1.18)
                    let height = minHeight + visualEnergy * (maxHeight - minHeight)
                    sample = CompactWaveSample(
                        height: min(maxHeight, max(minHeight + 1, height)),
                        isActive: true
                    )
                }

                samples.insert(sample, at: 0)
                if samples.count > maxSamples {
                    samples.removeLast()
                }
            }

            lastSampleTime += Double(steps) * sampleInterval
        }

        return CGFloat(max(0, min(1, (currentTime - lastSampleTime) / sampleInterval)))
    }
}

private struct CompactWaveform: View {
    let meter: CaptureAudioLevelMeter
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var history = CompactWaveHistory()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let fraction = history.update(
                    currentTime: time,
                    level: meter.current,
                    minHeight: minHeight,
                    maxHeight: maxHeight
                )

                let pitch: CGFloat = 4.5
                guard size.width >= barWidth else { return }

                let rightEdge = size.width - 1 - fraction * pitch
                let totalColumns = Int(ceil((size.width + pitch) / pitch)) + 1
                let activeColor = Color.white
                let inactiveColor = Color(
                    red: 138.0 / 255.0,
                    green: 138.0 / 255.0,
                    blue: 138.0 / 255.0
                )

                for index in 0..<totalColumns {
                    let x = rightEdge - CGFloat(index) * pitch
                    guard x >= -barWidth && x <= size.width else { continue }

                    let barHeight: CGFloat
                    let color: Color
                    if index < history.samples.count {
                        let sample = history.samples[index]
                        barHeight = sample.height
                        color = sample.isActive ? activeColor : inactiveColor
                    } else {
                        barHeight = minHeight
                        color = inactiveColor
                    }

                    let rect = CGRect(
                        x: x,
                        y: (size.height - barHeight) / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
