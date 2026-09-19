import SwiftData
import SwiftUI

struct MemoryView: View {
    @ObservedObject var store: MemoryStore
    @Binding var selection: UUID?
    @State private var search = ""
    @State private var status: MemoryStatus = .active
    @State private var editor: MemoryEditorMode?
    @State private var errorMessage: String?

    private var visibleEntries: [MemoryRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            entry.status == status && (query.isEmpty || entry.name.localizedStandardContains(query) || entry.notes.localizedStandardContains(query))
        }
    }

    var body: some View {
        List(selection: $selection) {
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle") }
            ForEach(visibleEntries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Label(entry.name, systemImage: entry.kind?.systemImage ?? "bookmark").lineLimit(2)
                    Text(entry.kind?.title ?? "个人记忆").font(.caption).foregroundStyle(.secondary)
                    Text(entry.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 6)
                .tag(entry.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if visibleEntries.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Label(search.isEmpty ? "暂无\(status.title)的个人记忆" : "没有匹配的个人记忆", systemImage: "person.text.rectangle")
                } description: {
                    Text(search.isEmpty ? "Morie 会从日常语音输入中自动学习你的项目、人际关系和偏好，并保存在这里。" : "试试其他搜索词或筛选条件。")
                }
            }
        }
        .navigationTitle("个人记忆")
        .navigationSubtitle("\(visibleEntries.count) 条个人记忆")
        .searchable(text: $search, prompt: "搜索个人记忆")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("筛选个人记忆", selection: $status) {
                    ForEach(MemoryStatus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Button("新增个人记忆", systemImage: "plus") { editor = .create }
            }
        }
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = "无法加载个人记忆。" }
        }
        .onChange(of: visibleEntries.map(\.id), initial: true) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
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

    var body: some View {
        Group {
            if let memory = store.entries.first(where: { $0.id == memoryID }) {
                ManagementDetailContent {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(memory.kind?.title ?? "个人记忆", systemImage: memory.kind?.systemImage ?? "bookmark")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(memory.name).font(.title).textSelection(.enabled)
                        Label(memory.origin?.title ?? "个人记忆", systemImage: memory.origin == .automatic ? "sparkles" : "pencil")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(memory.notes).lineSpacing(5).textSelection(.enabled)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("状态", value: memory.status?.title ?? "不可用")
                            Text(memory.status == .active
                                 ? "帮助 Morie 理解后续输入，同时保留你的原意。"
                                 : "保留供查阅，不再用于理解后续输入。")
                                .foregroundStyle(.secondary)
                            if memory.origin == .user {
                                Text("你的手动编辑优先于自动更新。").foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Label("用于理解输入", systemImage: "text.bubble") }
                    DisclosureGroup("来源与历史") {
                        VStack(alignment: .leading, spacing: 12) {
                            if memory.sourceCaptureIDs.isEmpty { Text("由你手动添加").foregroundStyle(.secondary) }
                            ForEach(Array(memory.sourceCaptureIDs.enumerated()), id: \.element) { index, id in
                                NavigationLink("来源输入 \(index + 1)") {
                                    ManagementDetailContent {
                                        CaptureMemorySource(captureID: id)
                                        ForEach(store.analyses.filter { $0.sourceCaptureID == id && $0.observations.contains(where: { $0.memoryID == memoryID }) }) { analysis in
                                            MemoryAnalysisSourceView(analysis: analysis)
                                        }
                                    }
                                    .navigationTitle("记忆来源")
                                }
                            }
                            if let previousID = memory.supersedesID {
                                NavigationLink("上一条记忆") { MemoryDetailView(store: store, memoryID: previousID) }
                            }
                            if let replacement = store.entries.first(where: { $0.supersedesID == memory.id }) {
                                NavigationLink("替代后的记忆") { MemoryDetailView(store: store, memoryID: replacement.id) }
                            }
                            LabeledContent("创建时间", value: memory.createdAt.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).year().month().day().hour().minute()))
                            LabeledContent("更新时间", value: memory.updatedAt.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).year().month().day().hour().minute()))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("编辑个人记忆", systemImage: "pencil") { editor = .edit(memoryID) }.disabled(memory.status == .superseded)
                        Menu("个人记忆操作", systemImage: "ellipsis") {
                            if memory.status == .active {
                                Button("归档个人记忆", systemImage: "archivebox") { perform { try store.archive(memoryID) } }
                            } else if memory.status == .archived {
                                Button("恢复个人记忆", systemImage: "arrow.uturn.backward") { perform { try store.restore(memoryID) } }
                            }
                            if memory.status != .superseded {
                                Button("替代个人记忆…", systemImage: "arrow.triangle.2.circlepath") { editor = .replace(memoryID) }
                            }
                            Divider()
                            Button("删除个人记忆…", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
                        }
                    }
                }
            } else {
                ContentUnavailableView("此个人记忆已不存在", systemImage: "person.text.rectangle")
            }
        }
        .navigationTitle("个人记忆")
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .confirmationDialog("删除这条个人记忆？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除个人记忆", role: .destructive) {
                perform { try store.delete(memoryID); if let onDelete { onDelete() } else { dismiss() } }
            }
        } message: {
            Text("此个人记忆将被删除，系统也不会再次自动学习同一主题。来源输入会保留，你仍可手动重新添加这个主题。")
        }
        .alert("无法更新个人记忆", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

enum MemoryEditorMode: Identifiable {
    case create, edit(UUID), replace(UUID)
    var id: String {
        switch self {
        case .create: "create"
        case .edit(let id): "edit-\(id)"
        case .replace(let id): "replace-\(id)"
        }
    }
    var title: String {
        switch self {
        case .create: "新增个人记忆"
        case .edit: "编辑个人记忆"
        case .replace: "替代个人记忆"
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
            Text(mode.title).font(.headline)
            Form {
                Picker("类型", selection: $draft.kind) { ForEach(MemoryKind.allCases) { Text($0.title).tag($0) } }
                TextField("主题", text: $draft.name)
                LabeledContent("个人信息") {
                    TextEditor(text: $draft.notes).frame(height: 140).accessibilityLabel("个人信息")
                }
                Text("在这里保存项目、人际关系和偏好。词语的正确写法请添加到字典。").foregroundStyle(.secondary)
                if case .replace = mode { Text("原有记忆会标记为“已替代”，仍可查阅。").foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 580, height: 480)
        .onAppear {
            do {
                switch mode {
                case .create: break
                case .edit(let id), .replace(let id):
                    guard let saved = try store.memory(id).draft else { throw MemoryStore.StoreError.memoryUnavailable }
                    draft = saved
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        do {
            switch mode {
            case .create: try store.create(draft)
            case .edit(let id): try store.update(id, draft: draft)
            case .replace(let id): try store.replace(id, with: draft)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct CaptureMemorySource: View {
    @Query private var captures: [CaptureRecord]
    init(captureID: UUID) { _captures = Query(filter: #Predicate<CaptureRecord> { $0.id == captureID }) }
    var body: some View {
        if let capture = captures.first {
            LabeledContent("记录时间", value: capture.createdAt.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).year().month().day().hour().minute()))
            if let app = capture.sourceApplicationName { LabeledContent("来源应用", value: app) }
            Text(capture.finalText).textSelection(.enabled)
        } else {
            Text("来源输入已删除，单独保存的个人记忆仍可查阅。").foregroundStyle(.secondary)
        }
    }
}
