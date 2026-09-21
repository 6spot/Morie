import Observation
import SwiftUI

private enum ControlCenterLayout {
    static let contentInset: CGFloat = 24
    static let readingMaxWidth: CGFloat = 760
}

struct ControlCenterScrollableContent<Content: View>: View {
    let maxWidth: CGFloat?
    @ViewBuilder let content: Content

    init(
        maxWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                content
            }
            .frame(
                maxWidth: maxWidth ?? .infinity,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(ControlCenterLayout.contentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ControlCenterReadingContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ControlCenterScrollableContent(
            maxWidth: ControlCenterLayout.readingMaxWidth
        ) {
            content
        }
    }
}

struct ControlCenterFormContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }
}

@MainActor
private struct ControlCenterRouteHost: View {
    let controller: AppController
    @Bindable var session: ControlCenterSession

    var body: some View {
        ControlCenterDetailHost {
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
