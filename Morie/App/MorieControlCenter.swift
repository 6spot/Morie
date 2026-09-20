import SwiftUI

enum ControlCenterMetrics {
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 260

    // This is the only outer content inset used by routed Control Center pages.
    // Feature pages must not add their own top-level padding/contentMargins.
    static let pageInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 24
    static let readingMaxWidth: CGFloat = 760
}

enum ControlCenterPageKind {
    case standard
    case workspace
}

struct ControlCenterGroup<Content: View>: View {
    let title: String
    let footer: String?
    private let content: Content

    init(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ControlCenterReadingContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(
                maxWidth: ControlCenterMetrics.readingMaxWidth,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentMargins(
            .horizontal,
            ControlCenterMetrics.pageInset,
            for: .scrollContent
        )
        .contentMargins(
            .vertical,
            ControlCenterMetrics.pageInset,
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

    var pageKind: ControlCenterPageKind {
        switch self {
        case .history, .diagnostics:
            .workspace
        case .overview, .dictionary, .memory, .settings, .permissions:
            .standard
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
            NavigationStack {
                ControlCenterRouteHost(
                    controller: controller,
                    section: selection ?? .overview,
                    selectedCaptureID: $selectedCaptureID,
                    selectedDictionaryEntry: $selectedDictionaryEntry,
                    overviewMetricsSnapshot: $overviewMetricsSnapshot
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onAppear {
            Diagnostics.record("ControlCenter", "Shell mounted")
        }
        .onDisappear {
            Diagnostics.record("ControlCenter", "Shell unmounted")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .morieShowSettings)
        ) { _ in
            selection = .settings
        }
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
private struct ControlCenterRouteHost: View {
    let controller: AppController
    let section: ControlCenterSection
    @Binding var selectedCaptureID: UUID?
    @Binding var selectedDictionaryEntry: UUID?
    @Binding var overviewMetricsSnapshot: OverviewMetricsSnapshot?

    @ViewBuilder
    var body: some View {
        switch section.pageKind {
        case .standard:
            ScrollView {
                routedPage
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .contentMargins(
                .horizontal,
                ControlCenterMetrics.pageInset,
                for: .scrollContent
            )
            .contentMargins(
                .vertical,
                ControlCenterMetrics.pageInset,
                for: .scrollContent
            )

        case .workspace:
            routedPage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(ControlCenterMetrics.pageInset)
        }
    }

    @ViewBuilder
    private var routedPage: some View {
        switch section {
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

struct ManagementDetailContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ControlCenterReadingContent {
            content
        }
    }
}
