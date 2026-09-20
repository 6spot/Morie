import SwiftData
import SwiftUI

enum ControlCenterLayout {
    static let contentMaxWidth: CGFloat = 920
    static let readingMaxWidth: CGFloat = 760
    static let horizontalInset: CGFloat = 28
    static let verticalInset: CGFloat = 24
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ControlCenterSidebar(selection: $selection)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .morieShowSettings)) { _ in
            selection = .settings
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(controller: controller)
        case .history:
            CaptureHistoryWorkspace(
                controller: controller,
                selection: $selectedCaptureID
            )
        case .memory:
            if let memory = controller.memory {
                NavigationStack {
                    MemoryView(store: memory)
                }
            }
        case .dictionary:
            if let dictionary = controller.dictionary {
                DictionaryView(
                    store: dictionary,
                    selection: $selectedDictionaryEntry
                )
            }
        case .settings:
            MorieSettingsView(controller: controller)
        case .permissions:
            PermissionManagementView(controller: controller)
        case .diagnostics:
            DiagnosticLogView()
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
        .navigationTitle("Morie")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
    }

    private func sidebarItem(_ section: ControlCenterSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}

@MainActor
private struct CaptureHistoryWorkspace: View {
    @ObservedObject var controller: AppController
    @Binding var selection: UUID?

    var body: some View {
        HSplitView {
            CaptureHistoryListPane(
                selection: $selection,
                canStartCapture: controller.canStartCapture,
                onRecord: controller.startCaptureOnly
            )
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)

            CaptureHistoryDetailPane(
                controller: controller,
                selectedCaptureID: selection
            )
            .frame(minWidth: 420)
        }
    }
}

@MainActor
private struct CaptureHistoryListPane: View {
    @Binding var selection: UUID?
    let canStartCapture: Bool
    let onRecord: () -> Void
    @State private var fetchLimit = 200

    var body: some View {
        CaptureHistoryQueryPane(
            limit: fetchLimit,
            selection: $selection,
            canStartCapture: canStartCapture,
            onRecord: onRecord,
            onLoadMore: { fetchLimit += 200 }
        )
        .id(fetchLimit)
    }
}

@MainActor
private struct CaptureHistoryQueryPane: View {
    @Query private var captures: [CaptureRecord]
    @Binding var selection: UUID?
    let limit: Int
    let canStartCapture: Bool
    let onRecord: () -> Void
    let onLoadMore: () -> Void

    init(
        limit: Int,
        selection: Binding<UUID?>,
        canStartCapture: Bool,
        onRecord: @escaping () -> Void,
        onLoadMore: @escaping () -> Void
    ) {
        self.limit = limit
        _selection = selection
        self.canStartCapture = canStartCapture
        self.onRecord = onRecord
        self.onLoadMore = onLoadMore
        _captures = Query(CaptureHistoryQuery.descriptor(limit: limit))
    }

    var body: some View {
        VStack(spacing: 0) {
            CaptureHistoryView(
                captures: captures,
                selection: $selection,
                canStartCapture: canStartCapture,
                onRecord: onRecord
            )

            if captures.count >= limit {
                Divider()
                Button("加载更早记录", action: onLoadMore)
                    .buttonStyle(.link)
                    .padding(.vertical, 8)
            }
        }
    }
}

@MainActor
private struct CaptureHistoryDetailPane: View {
    @ObservedObject var controller: AppController
    @Query private var captures: [CaptureRecord]
    let selectedCaptureID: UUID?

    init(controller: AppController, selectedCaptureID: UUID?) {
        self.controller = controller
        self.selectedCaptureID = selectedCaptureID
        let queryID = selectedCaptureID ?? UUID()
        _captures = Query(
            filter: #Predicate<CaptureRecord> { $0.id == queryID }
        )
    }

    var body: some View {
        NavigationStack {
            if let id = selectedCaptureID,
               let capture = captures.first,
               let history = controller.history {
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
