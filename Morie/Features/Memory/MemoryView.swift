import SwiftData
import SwiftUI

struct MemoryView: View {
    @ObservedObject var store: MemoryStore
    @Binding var selection: UUID?
    @AppStorage(PersonalMemorySettings.enabledDefaultsKey) private var memoryEnabled = true
    @State private var search = ""
    @State private var status: MemoryStatus = .active
    @State private var editor: MemoryEditorMode?
    @State private var errorMessage: String?

    private var visibleEntries: [MemoryRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            entry.status == status
                && (
                    query.isEmpty
                    || entry.name.localizedStandardContains(query)
                    || entry.notes.localizedStandardContains(query)
                )
        }
    }

    var body: some View {
        List(selection: $selection) {
            if !memoryEnabled {
                Label(
                    "个人记忆已关闭，已有内容仍会保留。",
                    systemImage: "pause.circle"
                )
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
            }

            ForEach(visibleEntries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(entry.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 6)
                .tag(entry.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if visibleEntries.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Label(
                        search.isEmpty
                            ? "暂无(status.title)的个人记忆"
                            : "没有匹配的个人记忆",
                        systemImage: "person.text.rectangle"
                    )
                } description: {
                    Text(
                        search.isEmpty
                            ? "Morie 会从日常输入中逐渐形成对你有用的上下文，并在后续输入中参考。"
                            : "试试其他搜索词或筛选条件。"
                    )
                }
            }
        }
        .navigationTitle("个人记忆")
        .navigationSubtitle("(visibleEntries.count) 条")
        .searchable(text: $search, prompt: "搜索个人记忆")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("筛选个人记忆", selection: $status) {
                    ForEach(MemoryStatus.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)

                Button("新增个人记忆", systemImage: "plus") {
                    editor = .create
                }
            }
        }
        .sheet(item: $editor) {
            MemoryEditorSheet(store: store, mode: $0)
        }
        .onAppear {
            do {
                try store.load()
                errorMessage = nil
            } catch {
                errorMessage = "无法加载个人记忆。"
            }
        }
        .onChange(of: visibleEntries.map(\.id), initial: true) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
    }
}

struct MemoryDetailView: View {
    @ObservedObject var store: MemoryStore
    let memoryID: UUID
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var editor: MemoryEditorMode?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    private var evidence: [MemoryEvidenceSnapshot] {
        store.evidence(for: memoryID)
    }

    var body: some View {
        Group {
            if let memory = store.entries.first(where: { $0.id == memoryID }) {
                ManagementDetailContent {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(memory.name)
                            .font(.title)
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

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent(
                                "状态",
                                value: memory.status?.title ?? "不可用"
                            )
                            Text(
                                memory.status == .active
                                    ? "Morie 会在与这段内容相关的后续输入中参考它，但不会把没有说出的背景补进正文。"
                                    : "这段内容保留供你查阅，不再用于理解后续输入。"
                            )
                            .foregroundStyle(.secondary)

                            if memory.origin == .user {
                                Text("你的手动修改始终优先于后续自动学习。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Morie 如何使用它", systemImage: "text.bubble")
                    }

                    DisclosureGroup("来源与历史") {
                        VStack(alignment: .leading, spacing: 16) {
                            if evidence.isEmpty {
                                Text(
                                    memory.sourceCaptureIDs.isEmpty
                                        ? "由你手动添加"
                                        : "来源证据暂不可用"
                                )
                                .foregroundStyle(.secondary)
                            }

                            ForEach(evidence) { item in
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
                                            CaptureMemorySource(
                                                captureID: item.sourceCaptureID
                                            )
                                            MemoryAnalysisSourceView(
                                                sourceText: item.sourceText
                                            )
                                        }
                                        .navigationTitle("记忆来源")
                                    }
                                    .buttonStyle(.link)
                                }
                            }

                            if let previousID = memory.supersedesID {
                                NavigationLink("上一条记忆") {
                                    MemoryDetailView(
                                        store: store,
                                        memoryID: previousID
                                    )
                                }
                            }

                            if let replacement = store.entries.first(
                                where: { $0.supersedesID == memory.id }
                            ) {
                                NavigationLink("替代后的记忆") {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("编辑个人记忆", systemImage: "pencil") {
                            editor = .edit(memoryID)
                        }
                        .disabled(memory.status == .superseded)

                        Menu("个人记忆操作", systemImage: "ellipsis") {
                            if memory.status == .active {
                                Button(
                                    "归档个人记忆",
                                    systemImage: "archivebox"
                                ) {
                                    perform { try store.archive(memoryID) }
                                }
                            } else if memory.status == .archived {
                                Button(
                                    "恢复个人记忆",
                                    systemImage: "arrow.uturn.backward"
                                ) {
                                    perform { try store.restore(memoryID) }
                                }
                            }

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
                    try store.delete(memoryID)
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

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            "edit-(id)"
        case .replace(let id):
            "replace-(id)"
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
    @ObservedObject var store: MemoryStore
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
                        throw MemoryStore.StoreError.memoryUnavailable
                    }
                    draft = saved
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            switch mode {
            case .create:
                try store.create(draft)
            case .edit(let id):
                try store.update(id, draft: draft)
            case .replace(let id):
                try store.replace(id, with: draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CaptureMemorySource: View {
    @Query private var captures: [CaptureRecord]

    init(captureID: UUID) {
        _captures = Query(
            filter: #Predicate<CaptureRecord> { $0.id == captureID }
        )
    }

    var body: some View {
        if let capture = captures.first {
            LabeledContent(
                "记录时间",
                value: capture.createdAt.formatted(
                    .dateTime
                        .locale(Locale(identifier: "zh-Hans"))
                        .year()
                        .month()
                        .day()
                        .hour()
                        .minute()
                )
            )
            if let app = capture.sourceApplicationName {
                LabeledContent("来源应用", value: app)
            }
            Text(capture.finalText)
                .textSelection(.enabled)
        } else {
            Text("来源输入已删除，独立保存的记忆证据仍可查阅。")
                .foregroundStyle(.secondary)
        }
    }
}
