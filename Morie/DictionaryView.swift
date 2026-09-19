import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @Binding var selection: UUID?
    @State private var search = ""
    @State private var showingEditor = false
    @State private var editingEntryID: UUID?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 180), spacing: 8, alignment: .leading)
    ]

    private var selectedEntry: DictionaryDisplayEntry? {
        guard let selection else { return nil }
        return store.displayEntries.first { $0.id == selection }
    }

    private var selectedUserEntryID: UUID? {
        guard selectedEntry?.isEditable == true else { return nil }
        return selectedEntry?.id
    }

    private var visibleEntries: [DictionaryDisplayEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.displayEntries.filter { entry in
            query.isEmpty || entry.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        ScrollView {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(visibleEntries) { entry in
                    let item = DictionaryWordItem(
                        entry: entry,
                        isSelected: selection == entry.id,
                        select: { selection = entry.id }
                    )
                    .help(entry.source.helpText)

                    if entry.isEditable {
                        item.contextMenu {
                            Button("编辑") { edit(entry.id) }
                            Button("删除…", role: .destructive) {
                                selection = entry.id
                                confirmsDeletion = true
                            }
                        }
                    } else {
                        item
                    }
                }
            }
            .padding(20)
        }
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
                    if let selectedUserEntryID { edit(selectedUserEntryID) }
                }
                .disabled(selectedUserEntryID == nil)
                Button("删除词语…", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
                .disabled(selectedUserEntryID == nil)
                Button("添加词语", systemImage: "plus", action: add)
            }
        }
        .sheet(isPresented: $showingEditor) {
            DictionaryEditorSheet(store: store, entryID: editingEntryID)
        }
        .confirmationDialog("删除这个字典词语？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除词语", role: .destructive) {
                guard let id = selectedUserEntryID else { return }
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

private struct DictionaryWordItem: View {
    let entry: DictionaryDisplayEntry
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        if isSelected {
            Button(action: select) {
                Text(entry.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: select) {
                Text(entry.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
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
