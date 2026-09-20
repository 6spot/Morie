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
        GridItem(
            .adaptive(minimum: 110, maximum: 190),
            spacing: 8,
            alignment: .leading
        )
    ]

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
            query.isEmpty
                || entry.name.localizedStandardContains(query)
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
        VStack(alignment: .leading, spacing: 28) {
            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
            }

            if search.isEmpty || !visibleUserEntries.isEmpty {
                dictionarySection(
                    title: "用户添加",
                    description: "你添加或确认过的词语，可以编辑和删除。"
                ) {
                    if visibleUserEntries.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "还没有自定义词语",
                                systemImage: "character.book.closed"
                            )
                        } description: {
                            Text(
                                "添加人名、产品名或专业术语，帮助语音识别。"
                            )
                        } actions: {
                            Button(
                                "添加词语",
                                systemImage: "plus",
                                action: add
                            )
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(
                            columns: columns,
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(visibleUserEntries) { entry in
                                userWord(entry)
                            }
                        }
                    }
                }
            }

            if !visibleBuiltInEntries.isEmpty {
                Divider()

                dictionarySection(
                    title: "系统内置",
                    description:
                        "用于增强语音识别，由 Morie 维护，不支持修改或删除。"
                ) {
                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(visibleBuiltInEntries) { entry in
                            builtInWord(entry)
                        }
                    }
                }
            }

            if visibleCount == 0 && errorMessage == nil {
                ContentUnavailableView {
                    Label(
                        "没有匹配的词语",
                        systemImage: "magnifyingglass"
                    )
                } description: {
                    Text("试试其他搜索词。")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                deleteSelectedEntry()
            }
        } message: {
            Text("已保存的输入和个人记忆会保留。")
        }
        .onAppear(perform: load)
        .onChange(
            of: visibleUserEntries.map(\.id),
            initial: true
        ) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
    }

    private func dictionarySection<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
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

    private func deleteSelectedEntry() {
        guard let id = selectedUserEntryID else { return }

        do {
            try store.delete(id)
            selection = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func userWord(
        _ entry: DictionaryDisplayEntry
    ) -> some View {
        Button {
            selection = entry.id
        } label: {
            HStack(spacing: 8) {
                Text(entry.name)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if selection == entry.id {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .help(entry.source.helpText)
        .contextMenu {
            Button("编辑") {
                edit(entry.id)
            }

            Button("删除…", role: .destructive) {
                selection = entry.id
                confirmsDeletion = true
            }
        }
    }

    private func builtInWord(
        _ entry: DictionaryDisplayEntry
    ) -> some View {
        HStack(spacing: 8) {
            Text(entry.name)
                .lineLimit(1)

            Spacer(minLength: 4)

            Image(systemName: "lock")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("系统内置词语，不支持修改或删除。")
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
                    save()
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
               let entry = store.entries.first(
                    where: { $0.id == entryID }
               ) {
                name = entry.name
            }

            isWordFocused = true
        }
        .onChange(of: name) {
            errorMessage = nil
        }
    }

    private func save() {
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
}
