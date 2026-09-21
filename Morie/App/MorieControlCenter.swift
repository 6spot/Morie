import Observation
import SwiftUI

private enum ControlCenterLayout {
    static let contentInset: CGFloat = 24
    static let readingMaxWidth: CGFloat = 760
    static let sidebarMinWidth: CGFloat = 190
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 260
}

struct ControlCenterScrollableContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(ControlCenterLayout.contentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ControlCenterReadingContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(
                maxWidth: ControlCenterLayout.readingMaxWidth,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(ControlCenterLayout.contentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ControlCenterSectionBlock<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            footer
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ControlCenterSectionBlock where Footer == EmptyView {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, content: content) {
            EmptyView()
        }
    }
}

struct ControlCenterCommandBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
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
@Observable
private final class ControlCenterSession {
    var selection: ControlCenterSection? = .overview
    var selectedCaptureID: UUID?
    var selectedDictionaryEntry: UUID?
    var overviewMetricsSnapshot: OverviewMetricsSnapshot?
    var columnVisibility: NavigationSplitViewVisibility = .all

    var currentSection: ControlCenterSection {
        selection ?? .overview
    }

    func open(_ section: ControlCenterSection) {
        selection = section
    }
}

@MainActor
struct MorieControlCenter: View {
    let controller: AppController

    @State private var session = ControlCenterSession()

    var body: some View {
        @Bindable var session = session

        NavigationSplitView(columnVisibility: $session.columnVisibility) {
            ControlCenterSidebar(selection: $session.selection)
        } detail: {
            NavigationStack {
                ControlCenterRouteHost(
                    controller: controller,
                    session: session
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onAppear {
            Diagnostics.record("ControlCenter", "Shell mounted")
            Diagnostics.recordMemory("control-center-mounted")
        }
        .onDisappear {
            Diagnostics.record("ControlCenter", "Shell unmounted")
            Diagnostics.recordMemory("control-center-unmounted")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .morieShowSettings)
        ) { _ in
            session.open(.settings)
        }
    }
}

private struct ControlCenterSidebar: View {
    @Binding var selection: ControlCenterSection?

    var body: some View {
        List(selection: $selection) {
            sidebarItem(.overview)

            Section("资料库") {
                sidebarItem(.history)
                sidebarItem(.dictionary)
                sidebarItem(.memory)
            }

            Section("应用") {
                sidebarItem(.settings)
                sidebarItem(.permissions)
                sidebarItem(.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: ControlCenterLayout.sidebarMinWidth,
            ideal: ControlCenterLayout.sidebarIdealWidth,
            max: ControlCenterLayout.sidebarMaxWidth
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

private struct ControlCenterDetailHost<Content: View>: View {
    let section: ControlCenterSection
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .navigationTitle(section.title)
    }
}

@MainActor
private struct ControlCenterRouteHost: View {
    let controller: AppController
    @Bindable var session: ControlCenterSession

    var body: some View {
        ControlCenterDetailHost(section: session.currentSection) {
            routedPage
        }
    }

    @ViewBuilder
    private var routedPage: some View {
        switch session.currentSection {
        case .overview:
            OverviewView(
                controller: controller,
                metricsSnapshot: $session.overviewMetricsSnapshot
            )

        case .history:
            CaptureHistoryWorkspace(
                controller: controller,
                selection: $session.selectedCaptureID
            )

        case .dictionary:
            if let dictionary = controller.dictionary {
                DictionaryView(
                    store: dictionary,
                    selection: $session.selectedDictionaryEntry
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
    @ViewBuilder let content: Content

    var body: some View {
        ControlCenterReadingContent {
            content
        }
    }
}
