import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @Binding var selection: UUID?
    @State private var search = ""
    @State private var showingEditor = false
    @State private var errorMessage: String?

    private var visibleEntries: [DictionaryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            query.isEmpty || ([entry.name] + entry.aliases).contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        List(selection: $selection) {
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle") }
            ForEach(visibleEntries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name).lineLimit(2)
                    if !entry.aliases.isEmpty {
                        Text(entry.aliases.joined(separator: "、")).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 6).tag(entry.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if visibleEntries.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Label(search.isEmpty ? "你的字典" : "没有匹配的词语", systemImage: "character.book.closed")
                } description: {
                    Text(search.isEmpty ? "添加人名、产品名和专业术语，帮助 Morie 正确识别。" : "试试其他搜索词。")
                } actions: {
                    if search.isEmpty { Button("添加词语", systemImage: "plus") { showingEditor = true } }
                }
            }
        }
        .navigationTitle("字典")
        .navigationSubtitle("\(visibleEntries.count) 个词语")
        .searchable(text: $search, prompt: "搜索词语和别名")
        .toolbar { Button("添加词语", systemImage: "plus") { showingEditor = true } }
        .sheet(isPresented: $showingEditor) { DictionaryEditorSheet(store: store) }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = "无法加载字典。" }
        }
        .onChange(of: visibleEntries.map(\.id), initial: true) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }
}

struct DictionaryDetailView: View {
    @ObservedObject var store: DictionaryStore
    let entryID: UUID
    let onDelete: () -> Void
    @State private var showingEditor = false
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let entry = store.entries.first(where: { $0.id == entryID }) {
                ManagementDetailContent {
                    Label("自定义词语", systemImage: "character.book.closed").foregroundStyle(.secondary)
                    Text(entry.name).font(.title).textSelection(.enabled)
                    Text("识别语音时，会将此词语作为拼写提示。").foregroundStyle(.secondary)
                    if !entry.aliases.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("自动替换以下别名").font(.headline)
                            ForEach(entry.aliases, id: \.self) { Text("\($0) → \(entry.name)").textSelection(.enabled) }
                            Text("仅在某个别名始终应该替换为此词语时添加。").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("更新时间", value: entry.updatedAt.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).year().month().day().hour().minute()))
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("编辑词语", systemImage: "pencil") { showingEditor = true }
                        Button("删除词语…", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
                    }
                }
            } else { ContentUnavailableView("此词语已不存在", systemImage: "character.book.closed") }
        }
        .navigationTitle("字典")
        .sheet(isPresented: $showingEditor) { DictionaryEditorSheet(store: store, entryID: entryID) }
        .confirmationDialog("删除这个字典词语？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除词语", role: .destructive) {
                do { try store.delete(entryID); onDelete() }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { Text("已保存的输入和个人记忆会保留。") }
        .alert("无法更新字典", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct DictionaryEditorSheet: View {
    @ObservedObject var store: DictionaryStore
    var entryID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var aliases = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(entryID == nil ? "添加字典词语" : "编辑字典词语").font(.headline)
            Form {
                TextField("正确写法", text: $name)
                LabeledContent("自动替换的别名（选填）") {
                    TextEditor(text: $aliases).frame(height: 100).accessibilityLabel("别名，每行一个")
                }
                Text("每行填写一个始终需要替换的别名。留空则仅作为拼写提示。")
                    .foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    do {
                        let draft = DictionaryDraft(name: name, aliases: aliases.split(whereSeparator: \.isNewline).map(String.init))
                        if let entryID { try store.update(entryID, draft: draft) }
                        else { try store.create(draft) }
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540, height: 400)
        .onAppear {
            if let entryID, let entry = store.entries.first(where: { $0.id == entryID }) {
                name = entry.name
                aliases = entry.aliases.joined(separator: "\n")
            }
        }
    }
}
