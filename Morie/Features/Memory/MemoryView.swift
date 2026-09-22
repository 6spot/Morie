import SwiftData
import SwiftUI

struct MemoryView: View {
    @ObservedObject var store: MemoryPresentationStore
    @Binding var search: String
    @Binding var editor: MemoryEditorMode?
    @AppStorage(PersonalMemorySettings.enabledDefaultsKey)
    private var memoryEnabled = true

    @State private var errorMessage: String?

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeLongTerm: [MorieMemoryDTO] {
        matching(
            store.entries.filter {
                $0.status == .active && $0.scope != .workingContext
            }
        )
    }

    private var recentContext: [MorieMemoryDTO] {
        matching(
            store.entries.filter {
                $0.status == .active && $0.scope == .workingContext
            }
        )
    }

    private var history: [MorieMemoryDTO] {
        matching(
            store.entries.filter {
                $0.status == .archived || $0.status == .superseded
            }
        )
    }

    private var hasVisibleMemory: Bool {
        !activeLongTerm.isEmpty
            || !recentContext.isEmpty
            || !history.isEmpty
    }

    var body: some View {
        ControlCenterPage {
            HStack(spacing: 8) {
                Text("\(activeLongTerm.count) 条长期")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(recentContext.count) 条近期")
                if !history.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(history.count) 条历史")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !memoryEnabled {
                Label(
                    "个人记忆已关闭。已有内容会保留，但 Morie 暂时不会继续学习，也不会在润色时使用这些内容。",
                    systemImage: "pause.circle"
                )
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
            }

            if !activeLongTerm.isEmpty {
                ControlCenterSectionBlock(
                    "长期记忆",
                    subtitle: "稳定且仍然有效的事实。Morie 会在相关输入中参考这些内容。"
                ) {
                    MemoryTopicRows(
                        entries: activeLongTerm,
                        store: store
                    )
                }
            }

            if !recentContext.isEmpty {
                if !activeLongTerm.isEmpty {
                    Divider()
                }

                ControlCenterSectionBlock(
                    "最近",
                    subtitle: "近期仍可能变化的上下文，不会被当作长期事实保存。"
                ) {
                    MemoryTopicRows(
                        entries: recentContext,
                        store: store,
                        showsDate: true
                    )
                }
            }

            if !history.isEmpty {
                if !activeLongTerm.isEmpty || !recentContext.isEmpty {
                    Divider()
                }

                ControlCenterSectionBlock(
                    "已归档与历史",
                    subtitle: "已归档或被新内容替代的记忆，仅供查阅。"
                ) {
                    MemoryTopicRows(
                        entries: history,
                        store: store,
                        showsStatus: true
                    )
                }
            }

            if !hasVisibleMemory && errorMessage == nil {
                ContentUnavailableView {
                    Label(
                        query.isEmpty
                            ? "Morie 还不了解你"
                            : "没有匹配的内容",
                        systemImage: "person.text.rectangle"
                    )
                } description: {
                    Text(
                        query.isEmpty
                            ? "继续正常使用即可。Morie 会逐渐形成有用的长期理解和近期上下文。"
                            : "试试其他搜索词。"
                    )
                } actions: {
                    if query.isEmpty {
                        Button("告诉 Morie 一件事", systemImage: "plus") {
                            editor = .create
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .searchable(
            text: $search,
            placement: .toolbar,
            prompt: Text("搜索个人记忆")
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("告诉 Morie 一件事", systemImage: "plus") {
                    editor = .create
                }
            }
        }
        .sheet(item: $editor) {
            MemoryEditorSheet(store: store, mode: $0)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            try await store.loadIfNeeded()
            errorMessage = nil
        } catch {
            errorMessage = "无法加载个人记忆。"
        }
    }

    private func matching(
        _ entries: [MorieMemoryDTO]
    ) -> [MorieMemoryDTO] {
        let result: [MorieMemoryDTO]

        if query.isEmpty {
            result = entries
        } else {
            result = entries.filter {
                $0.name.localizedStandardContains(query)
                    || $0.notes.localizedStandardContains(query)
            }
        }

        return result.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

private struct MemoryTopicRows: View {
    let entries: [MorieMemoryDTO]
    @ObservedObject var store: MemoryPresentationStore
    var showsDate = false
    var showsStatus = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                NavigationLink {
                    MemoryDetailView(
                        store: store,
                        memoryID: entry.id
                    )
                } label: {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(entry.notes)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        Spacer(minLength: 16)

                        if showsStatus {
                            Text(entry.status?.title ?? "")
                                .foregroundStyle(.tertiary)
                        } else if showsDate {
                            Text(
                                entry.updatedAt.formatted(
                                    .dateTime
                                        .locale(
                                            Locale(identifier: "zh-Hans")
                                        )
                                        .month()
                                        .day()
                                )
                            )
                            .foregroundStyle(.tertiary)
                        }

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if entry.id != entries.last?.id {
                    Divider()
                }
            }
        }
    }
}

struct MemoryDetailView: View {
    @ObservedObject var store: MemoryPresentationStore
    let memoryID: UUID
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var editor: MemoryEditorMode?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    private var evidence: [MorieMemoryEvidenceDTO] {
        store.evidence(for: memoryID)
    }

    var body: some View {
        Group {
            if let memory = store.entries.first(where: { $0.id == memoryID }) {
                ManagementDetailContent {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(memory.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        Label(
                            memory.origin?.title ?? "个人记忆",
                            systemImage: memory.origin == .automatic
                                ? "sparkles"
                                : "pencil"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Text(memory.notes)
                        .lineSpacing(5)
                        .textSelection(.enabled)

                    Divider()

                    ControlCenterSectionBlock(
                        "Morie 如何使用它",
                        subtitle: "这段内容只会在相关输入中作为理解上下文，不会替你补充没有说过的正文。"
                    ) {
                        LabeledContent(
                            "状态",
                            value: memory.status?.title ?? "不可用"
                        )

                        Text(
                            memory.status == .active
                                ? "当前会参与相关输入的理解与润色。"
                                : "当前仅保留供你查阅，不再参与后续输入。"
                        )
                        .foregroundStyle(.secondary)

                        if memory.origin == .user {
                            Text("你的手动修改始终优先于后续自动学习。")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    ControlCenterSectionBlock(
                        "来源与历史",
                        subtitle: "查看 Morie 为什么形成这段记忆，以及它是否替代过其他内容。"
                    ) {
                        if evidence.isEmpty {
                            Text(
                                memory.sourceCaptureIDs.isEmpty
                                    ? "由你手动添加"
                                    : "来源证据暂不可用"
                            )
                            .foregroundStyle(.secondary)
                        }

                        ForEach(evidence.indices, id: \.self) { index in
                            let item = evidence[index]

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.claim)
                                    .textSelection(.enabled)

                                Text(
                                    item.capturedAt.formatted(
                                        .dateTime
                                            .locale(Locale(identifier: "zh-Hans"))
                                            .year()
                                            .month()
                                            .day()
                                            .hour()
                                            .minute()
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                NavigationLink("查看来源输入") {
                                    ManagementDetailContent {
                                        CaptureMemorySource(evidence: item)
                                    }
                                    .navigationTitle("记忆来源")
                                }
                                .buttonStyle(.link)
                            }

                            if index < evidence.count - 1 {
                                Divider()
                            }
                        }

                        if let previousID = memory.supersedesID {
                            NavigationLink("查看上一条记忆") {
                                MemoryDetailView(
                                    store: store,
                                    memoryID: previousID
                                )
                            }
                        }

                        if let replacement = store.entries.first(
                            where: { $0.supersedesID == memory.id }
                        ) {
                            NavigationLink("查看替代后的记忆") {
                                MemoryDetailView(
                                    store: store,
                                    memoryID: replacement.id
                                )
                            }
                        }

                        LabeledContent(
                            "创建时间",
                            value: memory.createdAt.formatted(
                                .dateTime
                                    .locale(Locale(identifier: "zh-Hans"))
                                    .year()
                                    .month()
                                    .day()
                                    .hour()
                                    .minute()
                            )
                        )

                        LabeledContent(
                            "更新时间",
                            value: memory.updatedAt.formatted(
                                .dateTime
                                    .locale(Locale(identifier: "zh-Hans"))
                                    .year()
                                    .month()
                                    .day()
                                    .hour()
                                    .minute()
                            )
                        )
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("编辑个人记忆", systemImage: "pencil") {
                            editor = .edit(memoryID)
                        }
                        .disabled(memory.status == .superseded)

                        if memory.status == .active {
                            Button(
                                "归档个人记忆",
                                systemImage: "archivebox"
                            ) {
                                perform { try await store.archive(memoryID) }
                            }
                        } else if memory.status == .archived {
                            Button(
                                "恢复个人记忆",
                                systemImage: "arrow.uturn.backward"
                            ) {
                                perform { try await store.restore(memoryID) }
                            }
                        }

                        Menu("更多操作", systemImage: "ellipsis") {
                            if memory.status != .superseded {
                                Button(
                                    "替代个人记忆…",
                                    systemImage: "arrow.triangle.2.circlepath"
                                ) {
                                    editor = .replace(memoryID)
                                }
                            }

                            Divider()

                            Button(
                                "删除个人记忆…",
                                systemImage: "trash",
                                role: .destructive
                            ) {
                                confirmsDeletion = true
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "此个人记忆已不存在",
                    systemImage: "person.text.rectangle"
                )
            }
        }
        .navigationTitle("个人记忆")
        .sheet(item: $editor) {
            MemoryEditorSheet(store: store, mode: $0)
        }
        .confirmationDialog(
            "删除这条个人记忆？",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("删除个人记忆", role: .destructive) {
                perform {
                    try await store.delete(memoryID)
                    if let onDelete {
                        onDelete()
                    } else {
                        dismiss()
                    }
                }
            }
        } message: {
            Text(
                "这段记忆会被删除，并作为你明确删除过的主题阻止自动恢复。来源输入仍会保留；你也可以之后手动重新添加。"
            )
        }
        .alert(
            "无法更新个人记忆",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func perform(
        _ action: @escaping () async throws -> Void
    ) {
        Task {
            do {
                try await action()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum MemoryEditorMode: Identifiable {
    case create
    case edit(UUID)
    case replace(UUID)

    var id: String {
        switch self {
        case .create:
            "create"
        case .edit(let id):
            "edit-\(id)"
        case .replace(let id):
            "replace-\(id)"
        }
    }

    var title: String {
        switch self {
        case .create:
            "新增个人记忆"
        case .edit:
            "编辑个人记忆"
        case .replace:
            "替代个人记忆"
        }
    }
}

struct MemoryEditorSheet: View {
    @ObservedObject var store: MemoryPresentationStore
    let mode: MemoryEditorMode

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MemoryDraft()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(mode.title)
                .font(.headline)

            Form {
                TextField("主题", text: $draft.name)

                LabeledContent("内容") {
                    TextEditor(text: $draft.notes)
                        .frame(height: 160)
                        .accessibilityLabel("个人记忆内容")
                }

                Text(
                    "直接写下你希望 Morie 记住的内容。内部分类和生命周期由系统处理，不需要你维护。"
                )
                .foregroundStyle(.secondary)

                if case .replace = mode {
                    Text("原有内容会标记为“已替代”，仍可查阅。")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580, height: 480)
        .onAppear {
            do {
                switch mode {
                case .create:
                    break
                case .edit(let id), .replace(let id):
                    guard let saved = try store.memory(id).draft else {
                        throw MemoryPresentationStore.StoreError.memoryUnavailable
                    }
                    draft = saved
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        Task {
            do {
                switch mode {
                case .create:
                    try await store.create(draft)
                case .edit(let id):
                    try await store.update(id, draft: draft)
                case .replace(let id):
                    try await store.replace(id, with: draft)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CaptureMemorySource: View {
    let evidence: MorieMemoryEvidenceDTO

    var body: some View {
        LabeledContent(
            "记录时间",
            value: evidence.capturedAt.formatted(
                .dateTime
                    .locale(Locale(identifier: "zh-Hans"))
                    .year()
                    .month()
                    .day()
                    .hour()
                    .minute()
            )
        )

        Text(evidence.sourceText)
            .textSelection(.enabled)
    }
}
