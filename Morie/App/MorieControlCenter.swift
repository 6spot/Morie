import AppKit
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

struct ControlCenterPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ControlCenterScrollableContent {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
    let subtitle: String?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

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
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, subtitle: subtitle, content: content) {
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
    var columnVisibility: NavigationSplitViewVisibility = .all

    var currentSection: ControlCenterSection {
        selection ?? .overview
    }

    func open(_ section: ControlCenterSection) {
        selection = section
    }

    func resetPresentation() {
        selection = .overview
        selectedCaptureID = nil
        selectedDictionaryEntry = nil
        columnVisibility = .all
    }
}

@MainActor
@Observable
private final class ControlCenterPresentationState {
    var history: CaptureHistoryController?
    var overview = OverviewPageState()

    func prepare(history: CaptureHistoryController?) {
        if self.history == nil {
            self.history = history
        }
    }

    var dictionarySearch = ""
    var dictionaryShowingEditor = false
    var dictionaryEditingEntryID: UUID?
    var dictionaryConfirmsDeletion = false

    var memorySearch = ""
    var memoryEditor: MemoryEditorMode?

    var historySearch = ""
    var historyFilter: CaptureHistoryFilter = .all

    var diagnosticSearch = ""
    var diagnosticLevel: DiagnosticLevel?
    var diagnosticConfirmsClear = false

    var confirmsFactoryReset = false
    var factoryResetInProgress = false
    var factoryResetError: String?

    func reset() {
        history?.releasePresentationResources()
        history = nil
        overview.metricsSnapshot = nil

        dictionarySearch = ""
        dictionaryShowingEditor = false
        dictionaryEditingEntryID = nil
        dictionaryConfirmsDeletion = false

        memorySearch = ""
        memoryEditor = nil

        historySearch = ""
        historyFilter = .all

        diagnosticSearch = ""
        diagnosticLevel = nil
        diagnosticConfirmsClear = false

        confirmsFactoryReset = false
        factoryResetInProgress = false
        factoryResetError = nil
    }
}

@MainActor
struct MorieControlCenter: View {
    let controller: AppController

    @State private var session = ControlCenterSession()
    @State private var presentation = ControlCenterPresentationState()

    var body: some View {
        @Bindable var session = session

        NavigationSplitView(columnVisibility: $session.columnVisibility) {
            ControlCenterSidebar(selection: $session.selection)
        } detail: {
            NavigationStack {
                ControlCenterRouteHost(
                    controller: controller,
                    session: session,
                    presentation: presentation
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .onAppear {
            presentation.prepare(
                history: controller.makeControlCenterHistoryController()
            )
            Diagnostics.record("ControlCenter", "Shell mounted")
            Diagnostics.recordMemory("control-center-mounted")
        }
        .onDisappear {
            DiagnosticLogStore.shared.setPresentationVisible(false)
            presentation.reset()
            session.resetPresentation()

            Diagnostics.record("ControlCenter", "Shell unmounted")
            Diagnostics.recordMemory("control-center-unmounted")

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                Diagnostics.recordMemory("control-center-unmounted+1s")
                try? await Task.sleep(for: .seconds(4))
                Diagnostics.recordMemory("control-center-unmounted+5s")
            }
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

            Section("系统") {
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
    @Bindable var presentation: ControlCenterPresentationState

    var body: some View {
        ControlCenterDetailHost(section: session.currentSection) {
            routedPage
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                toolbarSearchSlot
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarFilterSlot
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarActionOne
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarActionTwo
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarActionThree
            }
        }
        .confirmationDialog(
            "恢复出厂设置？",
            isPresented: $presentation.confirmsFactoryReset,
            titleVisibility: .visible
        ) {
            Button("恢复出厂设置", role: .destructive) {
                presentation.factoryResetInProgress = true
                Task {
                    do {
                        await presentation.history?.cancelRecognitionAndWait()
                        try await controller.factoryReset()
                    } catch {
                        presentation.factoryResetInProgress = false
                        presentation.factoryResetError = error.localizedDescription
                    }
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "将永久删除历史记录、原始录音、字典、个人记忆、学习数据、诊断日志和外部 API 配置，并把所有 Morie 设置恢复默认。Morie 随后会退出。macOS 已授予的系统权限不会被撤销。"
            )
        }
        .alert(
            "恢复出厂设置失败",
            isPresented: Binding(
                get: { presentation.factoryResetError != nil },
                set: {
                    if !$0 {
                        presentation.factoryResetError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                presentation.factoryResetError = nil
            }
        } message: {
            Text(presentation.factoryResetError ?? "")
        }
    }

    @ViewBuilder
    private var routedPage: some View {
        switch session.currentSection {
        case .overview:
            OverviewView(
                controller: controller,
                state: presentation.overview
            )

        case .history:
            if let history = presentation.history {
                CaptureHistoryWorkspace(
                    controller: controller,
                    history: history,
                    selection: $session.selectedCaptureID,
                    search: $presentation.historySearch,
                    filter: $presentation.historyFilter
                )
            } else {
                unavailable("历史记录不可用")
            }

        case .dictionary:
            if let dictionary = controller.dictionary {
                DictionaryView(
                    store: dictionary,
                    selection: $session.selectedDictionaryEntry,
                    search: $presentation.dictionarySearch,
                    showingEditor: $presentation.dictionaryShowingEditor,
                    editingEntryID: $presentation.dictionaryEditingEntryID,
                    confirmsDeletion: $presentation.dictionaryConfirmsDeletion
                )
            } else {
                unavailable("字典不可用")
            }

        case .memory:
            if let memory = controller.memory {
                MemoryView(
                    store: memory,
                    search: $presentation.memorySearch,
                    editor: $presentation.memoryEditor
                )
            } else {
                unavailable("个人记忆不可用")
            }

        case .settings:
            MorieSettingsView(controller: controller)

        case .permissions:
            PermissionManagementView(controller: controller)

        case .diagnostics:
            DiagnosticLogView(
                search: $presentation.diagnosticSearch,
                level: $presentation.diagnosticLevel,
                confirmsClear: $presentation.diagnosticConfirmsClear
            )
        }
    }

    @ViewBuilder
    private var toolbarSearchSlot: some View {
        switch session.currentSection {
        case .history:
            toolbarSearchField(
                "搜索历史记录",
                text: $presentation.historySearch
            )

        case .dictionary:
            toolbarSearchField(
                "搜索词语",
                text: $presentation.dictionarySearch
            )

        case .memory:
            toolbarSearchField(
                "搜索个人记忆",
                text: $presentation.memorySearch
            )

        case .diagnostics:
            toolbarSearchField(
                "搜索诊断日志",
                text: $presentation.diagnosticSearch
            )

        case .overview, .settings, .permissions:
            toolbarPlaceholder(width: 220)
        }
    }

    @ViewBuilder
    private var toolbarFilterSlot: some View {
        switch session.currentSection {
        case .history:
            Picker("筛选记录", selection: $presentation.historyFilter) {
                ForEach(CaptureHistoryFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

        case .diagnostics:
            Picker("筛选日志", selection: $presentation.diagnosticLevel) {
                Text("全部日志")
                    .tag(nil as DiagnosticLevel?)

                ForEach(
                    [
                        DiagnosticLevel.info,
                        .warning,
                        .error,
                    ],
                    id: \.self
                ) {
                    Text($0.title).tag(Optional($0))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

        case .overview, .dictionary, .memory, .settings, .permissions:
            toolbarPlaceholder(width: 110)
        }
    }

    @ViewBuilder
    private var toolbarActionOne: some View {
        switch session.currentSection {
        case .history:
            Button(
                "开始录音",
                systemImage: "mic",
                action: controller.startCaptureOnly
            )
            .disabled(!controller.canStartCapture)

        case .dictionary:
            Button("编辑词语", systemImage: "pencil") {
                guard let id = selectedDictionaryUserEntryID else {
                    return
                }
                dictionaryEditingEntryID = id
                dictionaryShowingEditor = true
            }
            .disabled(selectedDictionaryUserEntryID == nil)

        case .memory:
            Button("告诉 Morie 一件事", systemImage: "plus") {
                memoryEditor = .create
            }

        case .settings:
            Button(
                "恢复出厂设置…",
                systemImage: "arrow.counterclockwise",
                role: .destructive
            ) {
                presentation.confirmsFactoryReset = true
            }
            .disabled(presentation.factoryResetInProgress || controller.isCaptureActive)

        case .permissions:
            Button("重新检查", systemImage: "arrow.clockwise") {
                Task {
                    await controller.setup.refresh()
                }
            }
            .disabled(permissionRefreshDisabled)

        case .diagnostics:
            Button(
                "复制当前筛选",
                systemImage: "line.3.horizontal.decrease.circle"
            ) {
                copyDiagnostics(filteredDiagnosticEntries)
            }

        case .overview:
            toolbarPlaceholder()
        }
    }

    @ViewBuilder
    private var toolbarActionTwo: some View {
        switch session.currentSection {
        case .dictionary:
            Button(
                "删除词语…",
                systemImage: "trash",
                role: .destructive
            ) {
                dictionaryConfirmsDeletion = true
            }
            .disabled(selectedDictionaryUserEntryID == nil)

        case .diagnostics:
            Button("复制全部日志", systemImage: "doc.on.doc") {
                copyDiagnostics(DiagnosticLogStore.shared.entries)
            }

        case .overview, .history, .memory, .settings, .permissions:
            toolbarPlaceholder()
        }
    }

    @ViewBuilder
    private var toolbarActionThree: some View {
        switch session.currentSection {
        case .dictionary:
            Button("添加词语", systemImage: "plus") {
                dictionaryEditingEntryID = nil
                dictionaryShowingEditor = true
            }

        case .diagnostics:
            Menu("诊断操作", systemImage: "ellipsis") {
                Button(
                    "在访达中显示日志文件",
                    systemImage: "doc.text.magnifyingglass"
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [DiagnosticLogStore.shared.logFileURL]
                    )
                }

                Divider()

                Button(
                    "清空诊断日志…",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    diagnosticConfirmsClear = true
                }
            }

        case .overview, .history, .memory, .settings, .permissions:
            toolbarPlaceholder()
        }
    }

    private func toolbarSearchField(
        _ prompt: String,
        text: Binding<String>
    ) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
    }

    private func toolbarPlaceholder(
        width: CGFloat = 28
    ) -> some View {
        Color.clear
            .frame(width: width, height: 1)
            .accessibilityHidden(true)
    }


    private var permissionRefreshDisabled: Bool {
        controller.setup.isRefreshing
            || controller.setup.activeRequest != nil
            || controller.capabilities.isBootstrapping
    }

    private var selectedDictionaryUserEntryID: UUID? {
        guard let dictionary = controller.dictionary,
              let selectedID = session.selectedDictionaryEntry,
              dictionary.displayEntries.first(
                  where: { $0.id == selectedID }
              )?.isEditable == true
        else {
            return nil
        }
        return selectedID
    }

    private var filteredDiagnosticEntries: [DiagnosticLogStore.Entry] {
        let query = presentation.diagnosticSearch
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DiagnosticLogStore.shared.entries.filter { entry in
            (diagnosticLevel == nil || entry.level == presentation.diagnosticLevel)
                && (
                    query.isEmpty
                        || entry.category.localizedStandardContains(query)
                        || entry.message.localizedStandardContains(query)
                )
        }
    }

    private func copyDiagnostics(
        _ entries: [DiagnosticLogStore.Entry]
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            DiagnosticLogStore.shared.text(for: entries),
            forType: .string
        )
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
