import SwiftUI

enum ControlCenterMetrics {
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 260
    static let contentInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 28
    static let readingMaxWidth: CGFloat = 760
    static let denseInset: CGFloat = 16
}

struct ControlCenterContentPage<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(
        spacing: CGFloat = ControlCenterMetrics.sectionSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentMargins(
            .horizontal,
            ControlCenterMetrics.contentInset,
            for: .scrollContent
        )
        .contentMargins(
            .vertical,
            ControlCenterMetrics.contentInset,
            for: .scrollContent
        )
    }
}

struct ControlCenterReadingPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: ControlCenterMetrics.readingMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentMargins(
            .horizontal,
            ControlCenterMetrics.contentInset,
            for: .scrollContent
        )
        .contentMargins(
            .vertical,
            ControlCenterMetrics.contentInset,
            for: .scrollContent
        )
    }
}

private enum ControlCenterSection: String, CaseIterable, Identifiable {
    case overview
    case history
    case dictionary
    case memory
    case settings
    case permissions
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "总览"
        case .history: "历史记录"
        case .dictionary: "字典"
        case .memory: "个人记忆"
        case .settings: "设置"
        case .permissions: "权限"
        case .diagnostics: "诊断"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .memory: "person.text.rectangle"
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
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                ControlCenterRoute(
                    controller: controller,
                    selection: selection ?? .overview,
                    selectedCaptureID: $selectedCaptureID,
                    selectedDictionaryEntry: $selectedDictionaryEntry,
                    overviewMetricsSnapshot: $overviewMetricsSnapshot
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("显示或隐藏边栏", systemImage: "sidebar.left") {
                    toggleSidebar()
                }
                .help("显示或隐藏边栏")
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .morieShowSettings)) { _ in
            selection = .settings
        }
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }
}

@MainActor
private struct ControlCenterRoute: View {
    let controller: AppController
    let selection: ControlCenterSection
    @Binding var selectedCaptureID: UUID?
    @Binding var selectedDictionaryEntry: UUID?
    @Binding var overviewMetricsSnapshot: OverviewMetricsSnapshot?

    @ViewBuilder
    var body: some View {
        switch selection {
        case .overview:
            OverviewView(
                controller: controller,
                metricsSnapshot: $overviewMetricsSnapshot
            )

        case .history:
            CaptureHistoryWorkspace(
                controller: controller,
                selection: $selectedCaptureID
            )

        case .dictionary:
            if let dictionary = controller.dictionary {
                DictionaryView(
                    store: dictionary,
                    selection: $selectedDictionaryEntry
                )
            } else {
                unavailable("字典不可用")
            }

        case .memory:
            if let memory = controller.memory {
                MemoryView(store: memory)
            } else {
                unavailable("个人记忆不可用")
            }

        case .settings:
            MorieSettingsView(controller: controller)

        case .permissions:
            PermissionManagementView(controller: controller)

        case .diagnostics:
            DiagnosticLogView()
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
        .navigationSplitViewColumnWidth(
            min: ControlCenterMetrics.sidebarMinWidth,
            ideal: ControlCenterMetrics.sidebarIdealWidth,
            max: ControlCenterMetrics.sidebarMaxWidth
        )
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

    @State private var search = ""
    @State private var filter: CaptureHistoryFilter = .all

    var body: some View {
        if let history = controller.history {
            HSplitView {
                CaptureHistoryListPane(
                    controller: controller,
                    history: history,
                    selection: $selection,
                    search: $search,
                    filter: $filter
                )
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)

                CaptureHistoryDetailPane(
                    controller: controller,
                    history: history,
                    selectedCaptureID: selection
                )
                .id(selection)
                .frame(minWidth: 360, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("历史记录")
            .searchable(text: $search, prompt: "搜索历史记录")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("筛选记录", selection: $filter) {
                        ForEach(CaptureHistoryFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)

                    Button(
                        "开始录音",
                        systemImage: "mic",
                        action: controller.startCaptureOnly
                    )
                    .disabled(!controller.canStartCapture)
                    .help("录音并保存到历史记录。")
                }
            }
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
            .navigationTitle("历史记录")
        }
    }
}

@MainActor
private struct CaptureHistoryListPane: View {
    @ObservedObject var controller: AppController
    @ObservedObject var history: CaptureHistoryController
    @Binding var selection: UUID?
    @Binding var search: String
    @Binding var filter: CaptureHistoryFilter

    var body: some View {
        VStack(spacing: 0) {
            CaptureHistoryView(
                captures: history.captures,
                selection: $selection,
                search: $search,
                filter: $filter,
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

struct ManagementDetailContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ControlCenterReadingPage {
            content
        }
    }
}
