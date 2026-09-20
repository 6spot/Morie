import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @Binding var selection: UUID?

    @State private var search = ""
    @State private var showingEditor = false
    @State private var editingEntryID: UUID?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    private var selectedEntry: DictionaryDisplayEntry? {
        guard let selection else { return nil }
        return store.displayEntries.first { $0.id == selection }
    }

    private var selectedUserEntryID: UUID? {
        guard selectedEntry?.isEditable == true else { return nil }
        return selectedEntry?.id
    }

    private var filteredEntries: [DictionaryDisplayEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.displayEntries.filter { entry in
            query.isEmpty || entry.name.localizedStandardContains(query)
        }
    }

    private var visibleUserEntries: [DictionaryDisplayEntry] {
        filteredEntries.filter(\.isEditable)
    }

    private var visibleBuiltInEntries: [DictionaryDisplayEntry] {
        filteredEntries.filter { !$0.isEditable }
    }

    private var visibleCount: Int {
        visibleUserEntries.count + visibleBuiltInEntries.count
    }

    var body: some View {
        List(selection: $selection) {
            if let errorMessage {
                Section {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            if search.isEmpty || !visibleUserEntries.isEmpty {
                Section {
                    if visibleUserEntries.isEmpty {
                        HStack {
                            Text("还没有添加词语。")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("添加词语", systemImage: "plus", action: add)
                        }
                    } else {
                        ForEach(visibleUserEntries) { entry in
                            Text(entry.name)
                                .tag(entry.id)
                                .contextMenu {
                                    Button("编辑") {
                                        edit(entry.id)
                                    }

                                    Button(
                                        "删除…",
                                        role: .destructive
                                    ) {
                                        selection = entry.id
                                        confirmsDeletion = true
                                    }
                                }
                                .help(entry.source.helpText)
                        }
                    }
                } header: {
                    Text("用户添加")
                } footer: {
                    Text("你添加或确认过的词语，可以编辑和删除。")
                }
            }

            if !visibleBuiltInEntries.isEmpty {
                Section {
                    ForEach(visibleBuiltInEntries) { entry in
                        HStack {
                            Text(entry.name)

                            Spacer()

                            Image(systemName: "lock")
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("系统内置，只读")
                        }
                        .foregroundStyle(.secondary)
                        .help("系统内置词语，不支持修改或删除。")
                    }
                } header: {
                    Text("系统内置")
                } footer: {
                    Text("用于增强语音识别，由 Morie 维护，不支持修改或删除。")
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if visibleCount == 0 && errorMessage == nil {
                ContentUnavailableView {
                    Label(
                        "没有匹配的词语",
                        systemImage: "character.book.closed"
                    )
                } description: {
                    Text("试试其他搜索词。")
                }
            }
        }
        .navigationTitle("字典")
        .navigationSubtitle("\(visibleCount) 个词语")
        .searchable(text: $search, prompt: "搜索词语")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("编辑词语", systemImage: "pencil") {
                    if let selectedUserEntryID {
                        edit(selectedUserEntryID)
                    }
                }
                .disabled(selectedUserEntryID == nil)

                Button(
                    "删除词语…",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    confirmsDeletion = true
                }
                .disabled(selectedUserEntryID == nil)

                Button("添加词语", systemImage: "plus", action: add)
            }
        }
        .sheet(isPresented: $showingEditor) {
            DictionaryEditorSheet(
                store: store,
                entryID: editingEntryID
            )
        }
        .confirmationDialog(
            "删除这个字典词语？",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("删除词语", role: .destructive) {
                guard let id = selectedUserEntryID else {
                    return
                }

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
            do {
                try store.loadIfNeeded()
                errorMessage = nil

                if selectedEntry?.isEditable != true {
                    selection = nil
                }
            } catch {
                errorMessage = "无法加载字典。"
            }
        }
        .onChange(
            of: visibleUserEntries.map(\.id),
            initial: true
        ) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
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
            Text(entryID == nil ? "添加词语" : "编辑词语")
                .font(.headline)

            Form {
                TextField(
                    "词语",
                    text: $name,
                    prompt: Text("例如：Morie")
                )
                .focused($isWordFocused)
            }
            .formStyle(.columns)

            Text("添加人名、产品名或专业术语，帮助语音识别。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(entryID == nil ? "添加" : "保存") {
                    do {
                        let draft = DictionaryDraft(name: name)
                        if let entryID {
                            try store.update(entryID, draft: draft)
                        } else {
                            try store.create(draft)
                        }
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if let entryID,
               let entry = store.entries.first(where: { $0.id == entryID }) {
                name = entry.name
            }
            isWordFocused = true
        }
        .onChange(of: name) {
            errorMessage = nil
        }
    }
}
