import AppKit
import SwiftUI

@MainActor
struct MorieSetupView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var setup: PermissionSetupController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    init(controller: AppController) {
        self.controller = controller
        _setup = ObservedObject(wrappedValue: controller.setup)
    }

    var body: some View {
        PermissionSetupContent(
            checks: setup.checks,
            isRefreshing: setup.isRefreshing,
            activeRequest: setup.activeRequest,
            isPreparing: controller.isBootstrapping,
            isInputActive: controller.isCaptureActive,
            canFinish: setup.isReady && controller.canCompleteSetup,
            preparationError: controller.setupError,
            onRefresh: { Task { await setup.refresh() } },
            onAction: { requirement in Task { await setup.performAction(for: requirement) } },
            onLater: { dismissWindow(id: "setup") },
            onFinish: {
                Task {
                    if controller.state == .ready {
                        await setup.refresh()
                    } else {
                        await controller.bootstrap(completingSetup: true)
                    }
                    if controller.canStartCapture {
                        openWindow(id: "control-center")
                        dismissWindow(id: "setup")
                    }
                }
            }
        )
        .task {
            if setup.checks.isEmpty {
                await setup.refresh()
            }
        }
    }
}

/// Data-only native presentation also used by isolated layout fixtures.
struct PermissionSetupContent: View {
    let checks: [CapabilityCheck]
    let isRefreshing: Bool
    let activeRequest: SetupRequirement?
    let isPreparing: Bool
    let isInputActive: Bool
    let canFinish: Bool
    let preparationError: String?
    let onRefresh: () -> Void
    let onAction: (SetupRequirement) -> Void
    let onLater: () -> Void
    let onFinish: () -> Void

    private var isBusy: Bool { isRefreshing || activeRequest != nil || isPreparing }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label("欢迎使用 Morie", systemImage: "waveform")
                    .font(.largeTitle)
                Text("说出想法，让 Morie 整理成保留原意的文字。")
                    .font(.title3)
                Text("先检查这台 Mac 的智能功能，并允许录音和输入所需的权限。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Form {
                if checks.isEmpty {
                    ProgressView("正在检查设备和权限…")
                } else {
                    Section("设备能力") {
                        ForEach(checks.filter { !$0.requirement.isPermission }) { check in
                            PermissionRequirementRow(
                                check: check, activeRequest: activeRequest, isBusy: isBusy,
                                onAction: onAction
                            )
                        }
                    }
                    Section {
                        ForEach(checks.filter { $0.requirement.isPermission }) { check in
                            PermissionRequirementRow(
                                check: check, activeRequest: activeRequest, isBusy: isBusy,
                                onAction: onAction
                            )
                        }
                    } header: {
                        Text("使用权限")
                    } footer: {
                        Text("从系统设置返回后会自动更新状态。你也可以随时重新检查。")
                    }
                }
                Section {
                    Label("你的录音和输入保存在这台 Mac 上，润色与个人记忆使用 Apple 本机智能。", systemImage: "lock.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if isPreparing {
                    ProgressView("正在准备语音资源，首次使用可能需要下载…")
                        .controlSize(.small)
                } else if let preparationError {
                    Label(preparationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(isInputActive ? "当前正在录音，结束后即可继续设置。" : (canFinish ? "一切就绪，可以开始使用了。" : "完成以上检查后即可开始使用。"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                HStack {
                    Button("稍后设置", action: onLater)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isPreparing)
                    Spacer()
                    if isRefreshing {
                        ProgressView().controlSize(.small).accessibilityLabel("正在检查")
                    }
                    Button("重新检查", systemImage: "arrow.clockwise", action: onRefresh)
                        .disabled(isBusy)
                    Button("开始使用", action: onFinish)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canFinish)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 680)
    }

}

private struct PermissionRequirementRow: View {
    let check: CapabilityCheck
    let activeRequest: SetupRequirement?
    let isBusy: Bool
    let onAction: (SetupRequirement) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: check.requirement.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(check.requirement.title).font(.headline)
                Text(check.requirement.explanation)
                    .foregroundStyle(.secondary)
                if let detail = check.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                if check.isReady || !check.requirement.isPermission || check.action == nil {
                    Label(check.statusTitle, systemImage: check.isReady ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(check.isReady ? Color.green : Color.secondary)
                        .font(.callout)
                }
                if let action = check.action, !check.isReady {
                    Button(check.actionTitle ?? action.title) { onAction(check.requirement) }
                        .controlSize(.small)
                        .disabled(isBusy)
                        .accessibilityLabel("\(check.requirement.title)：\(check.actionTitle ?? action.title)")
                }
                if activeRequest == check.requirement {
                    ProgressView().controlSize(.small).accessibilityLabel("正在等待授权结果")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
struct PermissionManagementView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var setup: PermissionSetupController

    init(controller: AppController) {
        self.controller = controller
        _setup = ObservedObject(wrappedValue: controller.setup)
    }

    private var isBusy: Bool {
        setup.isRefreshing
            || setup.activeRequest != nil
            || controller.isBootstrapping
    }

    var body: some View {
        ControlCenterContentPage {
            if setup.checks.isEmpty {
                ControlCenterSectionGroup("设备与权限") {
                    ProgressView("正在检查设备和权限…")
                }
            } else {
                ControlCenterSectionGroup("设备能力") {
                    ForEach(
                        setup.checks.filter { !$0.requirement.isPermission }
                    ) { check in
                        PermissionRequirementRow(
                            check: check,
                            activeRequest: setup.activeRequest,
                            isBusy: isBusy,
                            onAction: perform
                        )
                    }
                }

                ControlCenterSectionGroup(
                    "使用权限",
                    footer: "权限由 macOS 管理。从系统设置返回后，状态会自动更新。"
                ) {
                    ForEach(
                        setup.checks.filter { $0.requirement.isPermission }
                    ) { check in
                        PermissionRequirementRow(
                            check: check,
                            activeRequest: setup.activeRequest,
                            isBusy: isBusy,
                            onAction: perform
                        )
                    }
                }
            }

            if let error = controller.setupError {
                ControlCenterSectionGroup("状态") {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("权限")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("重新检查", systemImage: "arrow.clockwise") {
                    Task {
                        await setup.refresh()
                    }
                }
                .disabled(isBusy)

                if setup.isReady && !controller.canStartCapture {
                    Button("重新启用 Morie") {
                        Task {
                            await controller.bootstrap(
                                completingSetup: true
                            )
                        }
                    }
                    .disabled(
                        isBusy || controller.isCaptureActive
                    )
                }
            }
        }
        .task {
            if setup.checks.isEmpty {
                await setup.refresh()
            }
        }
    }

    private func perform(_ requirement: SetupRequirement) {
        Task {
            await setup.performAction(for: requirement)
        }
    }
}
