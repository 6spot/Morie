import SwiftUI

@MainActor
struct PermissionManagementView: View {
    let controller: any ControlCenterControlling
    @ObservedObject private var runtime: AppRuntimeController
    @ObservedObject private var capabilities: AppCapabilityController
    @ObservedObject private var setup: PermissionSetupController

    init(controller: any ControlCenterControlling) {
        self.controller = controller
        _runtime = ObservedObject(wrappedValue: controller.runtime)
        _capabilities = ObservedObject(
            wrappedValue: controller.capabilities
        )
        _setup = ObservedObject(wrappedValue: controller.setup)
    }

    private var isBusy: Bool {
        setup.isRefreshing
            || setup.activeRequest != nil
            || capabilities.isBootstrapping
    }

    var body: some View {
        ControlCenterPage {
            ControlCenterSectionBlock(
                "当前状态",
                subtitle: "Morie 只检查运行语音输入所需的设备能力和 macOS 权限。"
            ) {
                HStack(spacing: 10) {
                    Image(
                        systemName: setup.isReady
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                    .foregroundStyle(setup.isReady ? .secondary : .primary)

                    Text(
                        setup.isReady
                            ? "设备与权限已就绪"
                            : "还有项目需要处理"
                    )
                    .font(.headline)

                    Spacer()

                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if setup.isReady && !controller.canStartCapture {
                    Button("重新启用 Morie") {
                        Task {
                            await controller.bootstrap(
                                completingSetup: true
                            )
                        }
                    }
                    .disabled(isBusy || controller.isCaptureActive)
                }
            }

            Divider()

            if setup.checks.isEmpty {
                ControlCenterSectionBlock("正在检查") {
                    ProgressView("正在检查设备和权限…")
                }
            } else {
                ControlCenterSectionBlock(
                    "设备能力",
                    subtitle: "这些能力由当前 Mac 和系统资源决定。"
                ) {
                    capabilityRows(
                        setup.checks.filter {
                            !$0.requirement.isPermission
                        }
                    )
                }

                Divider()

                ControlCenterSectionBlock(
                    "使用权限",
                    subtitle: "权限由 macOS 管理。完成授权后可使用右上角“重新检查”立即刷新状态。"
                ) {
                    capabilityRows(
                        setup.checks.filter {
                            $0.requirement.isPermission
                        }
                    )
                }
            }

            if let error = capabilities.setupError {
                Divider()

                ControlCenterSectionBlock("需要注意") {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("重新检查", systemImage: "arrow.clockwise") {
                    Task {
                        await controller.refreshPermissions()
                    }
                }
                .disabled(isBusy)
            }
        }
        .task {
            if setup.checks.isEmpty {
                await controller.refreshPermissions()
            }
        }
    }

    @ViewBuilder
    private func capabilityRows(
        _ checks: [CapabilityCheck]
    ) -> some View {
        ForEach(checks.indices, id: \.self) { index in
            let check = checks[index]

            PermissionRequirementRow(
                check: check,
                activeRequest: setup.activeRequest,
                isBusy: isBusy,
                onAction: perform
            )

            if index < checks.count - 1 {
                Divider()
            }
        }
    }

    private func perform(_ requirement: SetupRequirement) {
        Task {
            await controller.performPermissionAction(
                requirement
            )
        }
    }
}
