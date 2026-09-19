import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @Binding var selection: UUID?
    @State private var search = ""
    @State private var showingEditor = false
    @State private var editingEntryID: UUID?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    private var selectedEntry: DictionaryEntry? {
        guard let selection else { return nil }
        return store.entries.first { $0.id == selection }
    }

    private var visibleEntries: [DictionaryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            query.isEmpty || entry.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        List(selection: $selection) {
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle") }
            ForEach(visibleEntries) { entry in
                Text(entry.name)
                    .lineLimit(2)
                    .padding(.vertical, 6)
                    .tag(entry.id)
                    .contextMenu {
                        Button("编辑") { edit(entry.id) }
                        Button("删除…", role: .destructive) {
                            selection = entry.id
                            confirmsDeletion = true
                        }
                    }
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
                    if search.isEmpty { Button("添加词语", systemImage: "plus", action: add) }
                }
            }
        }
        .navigationTitle("字典")
        .navigationSubtitle("\(visibleEntries.count) 个词语")
        .searchable(text: $search, prompt: "搜索词语")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("编辑词语", systemImage: "pencil") {
                    if let selectedEntry { edit(selectedEntry.id) }
                }
                .disabled(selectedEntry == nil)
                Button("删除词语…", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
                .disabled(selectedEntry == nil)
                Button("添加词语", systemImage: "plus", action: add)
            }
        }
        .sheet(isPresented: $showingEditor) {
            DictionaryEditorSheet(store: store, entryID: editingEntryID)
        }
        .confirmationDialog("删除这个字典词语？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除词语", role: .destructive) {
                guard let id = selectedEntry?.id else { return }
                do {
                    try store.delete(id)
                    selection = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("已保存的输入和个人记忆会保留。")
        }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = "无法加载字典。" }
        }
        .onChange(of: visibleEntries.map(\.id), initial: true) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    private func add() {
        editingEntryID = nil
        showingEditor = true
    }

    private func edit(_ id: UUID) {
        editingEntryID = id
        showingEditor = true
    }
}

struct DictionaryEditorSheet: View {
    @ObservedObject var store: DictionaryStore
    var entryID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var isWordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entryID == nil ? "添加词语" : "编辑词语").font(.headline)
            Form {
                TextField("词语", text: $name, prompt: Text("例如：Morie"))
                    .focused($isWordFocused)
            }
            .formStyle(.columns)
            Text("添加人名、产品名或专业术语，帮助语音识别。")
                .font(.callout).foregroundStyle(.secondary)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(entryID == nil ? "添加" : "保存") {
                    do {
                        let draft = DictionaryDraft(name: name)
                        if let entryID { try store.update(entryID, draft: draft) }
                        else { try store.create(draft) }
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 420).fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if let entryID, let entry = store.entries.first(where: { $0.id == entryID }) {
                name = entry.name
            }
            isWordFocused = true
        }
        .onChange(of: name) { errorMessage = nil }
    }
}
