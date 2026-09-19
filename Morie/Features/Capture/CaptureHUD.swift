import AppKit
import SwiftUI

@MainActor
final class CaptureHUDController {
    private let model = CaptureHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private enum Layout {
        static let contentWidth: CGFloat = 142
        static let contentHeight: CGFloat = 34
        static let effectInset: CGFloat = 6
        static let bottomOffset: CGFloat = 48

        static var panelSize: NSSize {
            NSSize(
                width: contentWidth + effectInset * 2,
                height: contentHeight + effectInset * 2
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

    func showSuccess(deliveryMode: CaptureDeliveryMode) {
        hideTask?.cancel()
        model.showFeedback(deliveryMode == .captureOnly ? .saved : .success)
        showPanel()
        Diagnostics.record("HUD", "Compact capture HUD showing success; mode=\(deliveryMode.rawValue)")

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showClipboardFallback() {
        hideTask?.cancel()
        model.showFeedback(.clipboardFallback)
        showPanel()
        Diagnostics.record("HUD", "Compact capture HUD showing clipboard fallback", level: .warning)

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showRecognitionFailure() {
        hideTask?.cancel()
        model.phase = .recognitionFailure
        showPanel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
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
        // `orderOut` does not tear down an NSHostingView. Keeping the hidden
        // panel alive therefore also kept CompactWaveform's 60 Hz
        // TimelineView rendering while Morie was idle. Release the view tree
        // so both the display-driven work and its render resources end with
        // the HUD's visible lifetime.
        panel?.contentView = nil
        panel = nil
        model.hide()
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
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
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

        let rootView = NSView(frame: NSRect(origin: .zero, size: size))
        rootView.autoresizingMask = [.width, .height]

        let glassFrame = NSRect(
            x: Layout.effectInset,
            y: Layout.effectInset,
            width: Layout.contentWidth,
            height: Layout.contentHeight
        )
        let glassView = NSGlassEffectView(frame: glassFrame)
        glassView.autoresizingMask = []
        glassView.style = .regular
        glassView.cornerRadius = Layout.contentHeight / 2
        glassView.tintColor = NSColor.black.withAlphaComponent(0.38)
        glassView.effectIsInteractive = true

        let hostingView = NSHostingView(rootView: CaptureHUDView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Layout.contentWidth, height: Layout.contentHeight)
        )
        hostingView.autoresizingMask = [.width, .height]
        glassView.contentView = hostingView
        rootView.addSubview(glassView)
        panel.contentView = rootView

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
            y: (visibleFrame.minY + Layout.bottomOffset - Layout.effectInset).rounded()
        )

        panel.setFrameOrigin(origin)
    }
}

final class CaptureAudioLevelMeter {
    var current: Double = 0
}

@MainActor
final class CaptureHUDModel: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case recording
        case processing
        case success
        case saved
        case clipboardFallback
        case recognitionFailure
        case failure
    }

    @Published var phase: Phase = .hidden
    @Published private(set) var recordingGeneration = UUID()
    @Published private(set) var feedbackGeneration = 0

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

    func hide() {
        audioLevel.current = 0
        phase = .hidden
    }

    func showFeedback(_ feedback: Phase) {
        feedbackGeneration += 1
        phase = feedback
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let contentWidth: CGFloat = 142
        static let contentHeight: CGFloat = 34
        static let contentInset: CGFloat = 3
        static let controlLaneWidth: CGFloat = 28
        static let controlVisualSize: CGFloat = 20
        static let waveformLaneWidth: CGFloat = 80
        static let waveformWidth: CGFloat = 56
        static let waveformHeight: CGFloat = 20
        static let waveformInset: CGFloat = 2
        static let waveformBarWidth: CGFloat = 2.5
        static let waveformMinHeight: CGFloat = 3
        static let waveformMaxHeight: CGFloat = 16

        static let innerHeight = contentHeight - contentInset * 2
    }

    var body: some View {
        phaseContent
            .frame(width: Layout.contentWidth, height: Layout.contentHeight)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .hidden:
            EmptyView()

        case .recording:
            HStack(spacing: 0) {
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Layout.controlVisualSize, height: Layout.controlVisualSize)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(.black.opacity(0.58))
                .frame(width: Layout.controlLaneWidth, height: Layout.innerHeight)
                .accessibilityLabel("取消录音")
                .help("取消录音")

                CompactWaveform(
                    meter: model.audioLevel,
                    reduceMotion: reduceMotion,
                    barWidth: Layout.waveformBarWidth,
                    minHeight: Layout.waveformMinHeight,
                    maxHeight: Layout.waveformMaxHeight
                )
                .id(model.recordingGeneration)
                .frame(
                    width: Layout.waveformWidth - Layout.waveformInset * 2,
                    height: Layout.waveformHeight - Layout.waveformInset * 2
                )
                .padding(Layout.waveformInset)
                .frame(width: Layout.waveformWidth, height: Layout.waveformHeight)
                .frame(width: Layout.waveformLaneWidth, height: Layout.innerHeight)
                .accessibilityLabel("麦克风输入电平")

                Button(action: model.confirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: Layout.controlVisualSize, height: Layout.controlVisualSize)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(.white.opacity(0.94))
                .frame(width: Layout.controlLaneWidth, height: Layout.innerHeight)
                .accessibilityLabel("完成录音")
                .help("完成录音")
            }
            .frame(
                width: Layout.contentWidth - Layout.contentInset * 2,
                height: Layout.innerHeight
            )
            .padding(Layout.contentInset)

        case .processing:
            ProgressView()
                .controlSize(.small)
                .frame(width: Layout.waveformWidth, height: Layout.waveformHeight)
                .accessibilityLabel("正在处理录音")

        case .success, .saved:
            Label(model.phase == .saved ? "已保存" : "已输入", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: model.feedbackGeneration)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(model.phase == .saved ? "录音和文字已保存到历史记录" : "文字已输入")

        case .clipboardFallback:
            Label("已复制到剪贴板", systemImage: "doc.on.clipboard.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: model.feedbackGeneration)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("输入位置不可用，文字已复制到剪贴板")

        case .recognitionFailure:
            Label("未识别，录音已保存", systemImage: "waveform.badge.exclamationmark")
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("未识别出文字，录音已保存，可在历史记录中重新识别")

        case .failure:
            Image(systemName: "exclamationmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: Layout.waveformWidth, height: Layout.waveformHeight)
                .accessibilityLabel("录音失败")
        }
    }
}

@MainActor
private final class CompactWaveDynamics {
    private var displayedLevel: CGFloat = 0
    private var previousTarget: CGFloat = 0
    private var lastFrameTime: TimeInterval = 0
    private var lastSampleTime: TimeInterval = 0
    private var recentLevels = Array(repeating: CGFloat.zero, count: 11)

    func update(currentTime: TimeInterval, rawLevel: Double, reduceMotion: Bool) -> [CGFloat] {
        if lastFrameTime == 0 {
            lastFrameTime = currentTime
        }

        let elapsed = min(max(currentTime - lastFrameTime, 0), 0.1)
        lastFrameTime = currentTime
        let normalized = max(0, min(1, CGFloat(rawLevel)))
        // Preserve quiet speech while still mapping normal speech across most
        // of the available height.
        let threshold: CGFloat = 0.10
        let ceiling: CGFloat = 0.88
        let baseTarget = normalized <= threshold
            ? 0
            : pow(min(1, (normalized - threshold) / (ceiling - threshold)), 0.78)
        // Rapid changes are themselves meaningful voice information. A short
        // transient accent makes consonants feel immediate without inventing
        // motion during silence.
        let transient = min(1, abs(baseTarget - previousTarget) * 2.4)
        previousTarget = baseTarget
        let target = min(1, baseTarget + transient * 0.28)

        guard !reduceMotion else {
            displayedLevel = target
            return Array(repeating: displayedLevel, count: recentLevels.count)
        }

        // Preserve continuity between 40 Hz microphone samples, but converge
        // within roughly one rendered frame so consonants do not turn into a
        // slow decorative pulse.
        let response = target > displayedLevel ? 140.0 : 95.0
        let blend = 1 - exp(-response * CGFloat(elapsed))
        displayedLevel += (target - displayedLevel) * blend

        if lastSampleTime == 0 || currentTime - lastSampleTime >= 1.0 / 60.0 {
            recentLevels.insert(displayedLevel, at: 0)
            recentLevels.removeLast()
            lastSampleTime = currentTime
        }

        return recentLevels
    }
}

private struct CompactWaveform: View {
    let meter: CaptureAudioLevelMeter
    let reduceMotion: Bool
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var dynamics = CompactWaveDynamics()

    // Matches the reference's immediate visual rhythm: quiet edges, an
    // irregular speech-like rise, and one clear center peak. The live meter
    // expands this profile instead of waiting for history to scroll in.
    private let profile: [CGFloat] = [
        0.22, 0.38, 0.55, 0.74, 0.60, 1.00,
        0.68, 0.82, 0.51, 0.34, 0.20,
    ]

    // Center is the newest sample. Moving away from center walks backward
    // through different moments rather than mirroring one shared scalar.
    private let sampleOrder = [10, 8, 6, 4, 2, 0, 1, 3, 5, 7, 9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let levels = dynamics.update(
                    currentTime: time,
                    rawLevel: meter.current,
                    reduceMotion: reduceMotion
                )
                let pitch: CGFloat = 4.95
                guard size.width >= barWidth else { return }

                let totalColumns = profile.count
                let usedWidth = CGFloat(totalColumns - 1) * pitch + barWidth
                let leading = (size.width - usedWidth) / 2

                for index in 0..<totalColumns {
                    let envelope = profile[index]
                    let historicalLevel = levels[sampleOrder[index]]
                    // Keep the recognizable center-weighted resting silhouette,
                    // but reserve most of the available height for live speech.
                    let restingHeight = minHeight + envelope * 1.5
                    // Edge bars remain alive while the center retains the
                    // largest travel. Avoid a symmetric dead-zone at either end.
                    let activityWeight = 0.34 + 0.66 * pow(envelope, 1.55)
                    let barHeight = restingHeight
                        + activityWeight * historicalLevel * (maxHeight - restingHeight)
                    let color: Color = levels[0] > 0.01 ? .primary : .secondary

                    let rect = CGRect(
                        x: leading + CGFloat(index) * pitch,
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
