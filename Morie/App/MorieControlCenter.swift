import SwiftUI

enum ControlCenterLayout {
    static let contentMaxWidth: CGFloat = 920
    static let readingMaxWidth: CGFloat = 760
    // Keep ordinary right-hand pages on one System Settings-like inset grid.
    // Using one value for both axes keeps the title/content baseline visually
    // aligned with the native sidebar instead of giving each page its own padding.
    static let contentInset: CGFloat = 24
    static let horizontalInset: CGFloat = contentInset
    static let verticalInset: CGFloat = contentInset
}

extension View {
    func controlCenterScrollMargins(
        horizontal: CGFloat = ControlCenterLayout.horizontalInset,
        vertical: CGFloat = ControlCenterLayout.verticalInset
    ) -> some View {
        contentMargins(.horizontal, horizontal, for: .scrollContent)
            .contentMargins(.vertical, vertical, for: .scrollContent)
    }
}

struct ControlCenterScrollPage<Content: View>: View {
    let maxWidth: CGFloat
    let spacing: CGFloat
    private let content: Content

    init(
        maxWidth: CGFloat = ControlCenterLayout.contentMaxWidth,
        spacing: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .controlCenterScrollMargins()
    }
}

private enum ControlCenterSection: String, CaseIterable, Identifiable {
    case overview
    case history
    case memory
    case dictionary
    case settings
    case permissions
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "总览"
        case .history: "历史记录"
        case .memory: "个人记忆"
        case .dictionary: "字典"
        case .settings: "设置"
        case .permissions: "权限"
        case .diagnostics: "诊断"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        case .memory: "person.text.rectangle"
        case .dictionary: "character.book.closed"
        case .settings: "gearshape"
        case .permissions: "lock.shield"
        case .diagnostics: "ladybug"
        }
    }
}

@MainActor
struct MorieControlCenter: View {
    let controller: AppController

    @State private var selection: ControlCenterSection? = .overview
    @State private var selectedCaptureID: UUID?
    @State private var selectedDictionaryEntry: UUID?
    @State private var overviewMetricsSnapshot: OverviewMetricsSnapshot?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ControlCenterSidebar(selection: $selection)
        } detail: {
            ControlCenterDetailHost(
                controller: controller,
                selection: $selection,
                selectedCaptureID: $selectedCaptureID,
                selectedDictionaryEntry: $selectedDictionaryEntry,
                overviewMetricsSnapshot: $overviewMetricsSnapshot
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .morieShowSettings)) { _ in
            selection = .settings
        }
    }
}

@MainActor
private struct ControlCenterDetailHost: View {
    let controller: AppController
    @Binding var selection: ControlCenterSection?
    @Binding var selectedCaptureID: UUID?
    @Binding var selectedDictionaryEntry: UUID?
    @Binding var overviewMetricsSnapshot: OverviewMetricsSnapshot?

    var body: some View {
        Group {
            if (selection ?? .overview) == .history {
                CaptureHistoryWorkspace(
                    controller: controller,
                    selection: $selectedCaptureID
                )
            } else {
                NavigationStack {
                    standardPage
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var standardPage: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(
                controller: controller,
                metricsSnapshot: $overviewMetricsSnapshot
            )

        case .memory:
            if let memory = controller.memory {
                MemoryView(store: memory)
            } else {
                unavailable("个人记忆不可用")
            }

        case .dictionary:
            if let dictionary = controller.dictionary {
                DictionaryView(
                    store: dictionary,
                    selection: $selectedDictionaryEntry
                )
            } else {
                unavailable("字典不可用")
            }

        case .settings:
            MorieSettingsView(controller: controller)

        case .permissions:
            PermissionManagementView(controller: controller)

        case .diagnostics:
            DiagnosticLogView()

        case .history:
            EmptyView()
        }
    }

    private func unavailable(_ title: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "exclamationmark.triangle",
            description: Text("记录存储尚未初始化。")
        )
    }
}

private struct ControlCenterSidebar: View {
    @Binding var selection: ControlCenterSection?
    @AppStorage("sidebar.libraryExpanded") private var libraryExpanded = true
    @AppStorage("sidebar.appExpanded") private var appExpanded = true

    var body: some View {
        List(selection: $selection) {
            sidebarItem(.overview)

            Section("资料库", isExpanded: $libraryExpanded) {
                sidebarItem(.history)
                sidebarItem(.dictionary)
                sidebarItem(.memory)
            }

            Section("应用", isExpanded: $appExpanded) {
                sidebarItem(.settings)
                sidebarItem(.permissions)
                sidebarItem(.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Morie")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        .onAppear {
            Diagnostics.record("ControlCenter", "Sidebar mounted")
        }
        .onDisappear {
            Diagnostics.record("ControlCenter", "Sidebar unmounted")
        }
    }

    private func sidebarItem(_ section: ControlCenterSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}

@MainActor
private struct CaptureHistoryWorkspace: View {
    let controller: AppController
    @Binding var selection: UUID?

    var body: some View {
        if let history = controller.history {
            HSplitView {
                NavigationStack {
                    CaptureHistoryListPane(
                        controller: controller,
                        history: history,
                        selection: $selection
                    )
                }
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 340)

                CaptureHistoryDetailPane(
                    controller: controller,
                    history: history,
                    selectedCaptureID: selection
                )
                .id(selection)
                .frame(minWidth: 320, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                history.setListVisible(true)
            }
            .onDisappear {
                history.setListVisible(false)
            }
        } else {
            ContentUnavailableView(
                "历史记录不可用",
                systemImage: "exclamationmark.triangle",
                description: Text("记录存储尚未初始化。")
            )
        }
    }
}

@MainActor
private struct CaptureHistoryListPane: View {
    @ObservedObject var controller: AppController
    @ObservedObject var history: CaptureHistoryController
    @Binding var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            CaptureHistoryView(
                captures: history.captures,
                selection: $selection,
                canStartCapture: controller.canStartCapture,
                onRecord: controller.startCaptureOnly
            )

            if history.canLoadMoreCaptures {
                Divider()
                Button("加载更早记录") {
                    history.loadMoreCaptures()
                }
                .buttonStyle(.link)
                .padding(.vertical, 8)
            }
        }
        .overlay {
            if history.captures.isEmpty, let message = history.listError {
                ContentUnavailableView(
                    "无法加载历史记录",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
    }
}

@MainActor
private struct CaptureHistoryDetailPane: View {
    @ObservedObject var controller: AppController
    @ObservedObject var history: CaptureHistoryController
    let selectedCaptureID: UUID?

    private var capture: CaptureRecord? {
        guard let selectedCaptureID else { return nil }
        return history.captures.first { $0.id == selectedCaptureID }
    }

    var body: some View {
        NavigationStack {
            if let id = selectedCaptureID,
               let capture {
                CaptureDetailView(
                    capture: capture,
                    captureID: id,
                    history: history,
                    canRecognize: controller.canStartCapture,
                    onRecognize: controller.recognizeHistoryCapture
                )
            } else {
                ContentUnavailableView(
                    "选择一条记录",
                    systemImage: "waveform",
                    description: Text("在这里查看保存的文字、识别结果和原始录音。")
                )
            }
        }
    }
}

struct ManagementDetailContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ControlCenterScrollPage(
            maxWidth: ControlCenterLayout.readingMaxWidth
        ) {
            content
        }
    }
}
