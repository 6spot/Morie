import SwiftData
import SwiftUI

struct MemoryView: View {
    @ObservedObject var store: MemoryStore
    @AppStorage(PersonalMemorySettings.enabledDefaultsKey) private var memoryEnabled = true
    @State private var search = ""
    @State private var editor: MemoryEditorMode?
    @State private var errorMessage: String?

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeLongTerm: [MemoryRecord] {
        matching(
            store.entries.filter {
                $0.status == .active && $0.scope != .workingContext
            }
        )
    }

    private var recentContext: [MemoryRecord] {
        matching(
            store.entries.filter {
                $0.status == .active && $0.scope == .workingContext
            }
        )
    }

    private var history: [MemoryRecord] {
        matching(
            store.entries.filter {
                $0.status == .archived || $0.status == .superseded
            }
        )
    }

    private var hasVisibleMemory: Bool {
        !activeLongTerm.isEmpty || !recentContext.isEmpty || !history.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Morie 了解你的这些内容")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("这些内容来自你日常使用 Morie 时表达过的信息，并会随着新的输入持续更新。")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if !memoryEnabled {
                        Label(
                            "个人记忆已关闭。已有内容会保留，但 Morie 暂时不会继续学习或在润色时使用它们。",
                            systemImage: "pause.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }

                if !activeLongTerm.isEmpty {
                    MemoryNarrativeGroup(
                        entries: activeLongTerm,
                        store: store
                    )
                }

                if !recentContext.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("最近")
                            .font(.title2)
                            .fontWeight(.semibold)

                        MemoryNarrativeGroup(
                            entries: recentContext,
                            store: store,
                            showsDate: true
                        )
                    }
                }

                if !history.isEmpty {
                    DisclosureGroup("已归档与历史") {
                        MemoryNarrativeGroup(
                            entries: history,
                            store: store,
                            showsStatus: true
                        )
                        .padding(.top, 16)
                    }
                    .font(.headline)
                }

                if !hasVisibleMemory && errorMessage == nil {
                    ContentUnavailableView {
                        Label(
                            query.isEmpty ? "Morie 还不了解你" : "没有匹配的内容",
                            systemImage: "person.text.rectangle"
                        )
                    } description: {
                        Text(
                            query.isEmpty
                                ? "继续正常使用即可。Morie 会在空闲时逐渐形成有用的长期理解和近期上下文。"
                                : "试试其他搜索词。"
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 56)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("个人记忆")
        .searchable(text: $search, prompt: "搜索 Morie 记住的内容")
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
        .onAppear {
            do {
                try store.load()
                errorMessage = nil
            } catch {
                errorMessage = "无法加载个人记忆。"
            }
        }
    }

    private func matching(_ entries: [MemoryRecord]) -> [MemoryRecord] {
        let result: [MemoryRecord]
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

private struct MemoryNarrativeGroup: View {
    let entries: [MemoryRecord]
    @ObservedObject var store: MemoryStore
    var showsDate = false
    var showsStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(entries) { entry in
                NavigationLink {
                    MemoryDetailView(store: store, memoryID: entry.id)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 12)

                            if showsStatus {
                                Text(entry.status?.title ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else if showsDate {
                                Text(
                                    entry.updatedAt.formatted(
                                        .dateTime
                                            .locale(Locale(identifier: "zh-Hans"))
                                            .month()
                                            .day()
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }

                        Text(entry.notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
