import SwiftData
import SwiftUI

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

    var isLibrary: Bool { self == .history || self == .memory || self == .dictionary }
}

@MainActor
struct MorieControlCenter: View {
    @ObservedObject var controller: AppController
    @State private var selection: ControlCenterSection? = .overview
    @State private var selectedCaptureID: UUID?
    @State private var selectedMemory: UUID?
    @State private var selectedDictionaryEntry: UUID?
    @State private var isSidebarVisible = true
    @AppStorage("sidebar.libraryExpanded") private var libraryExpanded = true
    @AppStorage("sidebar.appExpanded") private var appExpanded = true

    var body: some View {
        Group {
            if selection == .dictionary {
                NavigationSplitView(columnVisibility: columnVisibility(isLibrary: false)) {
                    sidebar
                } detail: {
                    if let dictionary = controller.dictionary {
                        DictionaryView(store: dictionary, selection: $selectedDictionaryEntry)
                    }
                }
            } else if (selection ?? .overview).isLibrary {
                NavigationSplitView(columnVisibility: columnVisibility(isLibrary: true)) {
                    sidebar
                } content: {
                    libraryList
                        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
                } detail: {
                    libraryDetail
                        .navigationSplitViewColumnWidth(min: 420, ideal: 600)
                }
            } else {
                NavigationSplitView(columnVisibility: columnVisibility(isLibrary: false)) {
                    sidebar
                } detail: {
                    switch selection {
                    case .overview, nil:
                        OverviewView(controller: controller)
                    case .settings:
                        MorieSettingsView(controller: controller)
                    case .permissions:
                        PermissionManagementView(controller: controller)
                    case .diagnostics:
                        DiagnosticLogView()
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .morieShowSettings)) { _ in
            selection = .settings
        }
    }

    private func columnVisibility(isLibrary: Bool) -> Binding<NavigationSplitViewVisibility> {
        // Hiding a sidebar means two columns in the library, but detail-only
        // in Diagnostics. Preserve one user choice across both native layouts.
        Binding(
            get: { isSidebarVisible ? .all : (isLibrary ? .doubleColumn : .detailOnly) },
            set: { visibility in
                isSidebarVisible = visibility == .all || visibility == .automatic
                    || (!isLibrary && visibility == .doubleColumn)
            }
        )
    }

    private var sidebar: some View {
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
        Label(section.title, systemImage: section.systemImage).tag(section)
    }

    @ViewBuilder
    private var libraryList: some View {
        switch selection ?? .history {
        case .history:
            CaptureHistoryListPane(
                selection: $selectedCaptureID,
                canStartCapture: controller.canStartCapture,
                onRecord: controller.startCaptureOnly
            )
        case .dictionary:
            EmptyView()
        case .memory:
            if let memory = controller.memory {
                MemoryView(store: memory, selection: $selectedMemory)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var libraryDetail: some View {
        switch selection ?? .history {
        case .history:
            CaptureHistoryDetailPane(
                controller: controller,
                selectedCaptureID: selectedCaptureID
            )
            .id(selectedCaptureID)
        case .memory:
            NavigationStack {
                if let memory = controller.memory, let selectedMemory {
                    MemoryDetailView(store: memory, memoryID: selectedMemory, onDelete: { self.selectedMemory = nil })
                } else {
                    ContentUnavailableView(
                        "选择一条个人记忆",
                        systemImage: "text.book.closed",
                        description: Text("在这里查看从日常输入中自动学习的个人信息。")
                    )
                }
            }
            .id(selectedMemory)
        case .dictionary:
            EmptyView()
        default:
            EmptyView()
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

enum CaptureHistoryQuery {
    static func descriptor(limit: Int) -> FetchDescriptor<CaptureRecord> {
        let capturing = CaptureLifecycle.capturing.rawValue
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.lifecycleRawValue != capturing },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
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
        _captures = Query(filter: #Predicate<CaptureRecord> { $0.id == queryID })
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

/// A reading surface shared by Capture and Memory details. Controls stay native.
struct ManagementDetailContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
