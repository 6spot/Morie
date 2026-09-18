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
                        Text(entry.aliases.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 6).tag(entry.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if visibleEntries.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Label(search.isEmpty ? "Your Dictionary" : "No Matching Words", systemImage: "character.book.closed")
                } description: {
                    Text(search.isEmpty ? "Add names, products and technical terms so Morie recognizes your words." : "Try another search.")
                } actions: {
                    if search.isEmpty { Button("Add Word", systemImage: "plus") { showingEditor = true } }
                }
            }
        }
        .navigationTitle("Dictionary")
        .navigationSubtitle(visibleEntries.count == 1 ? "1 word" : "\(visibleEntries.count) words")
        .searchable(text: $search, prompt: "Search words and aliases")
        .toolbar { Button("Add Word", systemImage: "plus") { showingEditor = true } }
        .sheet(isPresented: $showingEditor) { DictionaryEditorSheet(store: store) }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = "Could not load the dictionary." }
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
                    Label("Custom Word", systemImage: "character.book.closed").foregroundStyle(.secondary)
                    Text(entry.name).font(.title).textSelection(.enabled)
                    Text("Used as a spelling hint during speech recognition.").foregroundStyle(.secondary)
                    if !entry.aliases.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Always Replace These Aliases").font(.headline)
                            ForEach(entry.aliases, id: \.self) { Text("\($0) → \(entry.name)").textSelection(.enabled) }
                            Text("Only add an alias when it should always become this word.").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Updated", value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Edit Word", systemImage: "pencil") { showingEditor = true }
                        Button("Delete Word…", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
                    }
                }
            } else { ContentUnavailableView("Word No Longer Available", systemImage: "character.book.closed") }
        }
        .navigationTitle("Dictionary")
        .sheet(isPresented: $showingEditor) { DictionaryEditorSheet(store: store, entryID: entryID) }
        .confirmationDialog("Delete this dictionary word?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Word", role: .destructive) {
                do { try store.delete(entryID); onDelete() }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { Text("Saved input and personal memories are kept.") }
        .alert("Couldn’t Update Dictionary", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
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
            Text(entryID == nil ? "Add Dictionary Word" : "Edit Dictionary Word").font(.headline)
            Form {
                TextField("Correct Spelling", text: $name)
                LabeledContent("Always Replace (Optional)") {
                    TextEditor(text: $aliases).frame(height: 100).accessibilityLabel("Aliases, one per line")
                }
                Text("Add one alias per line only when it should always be replaced. Leave this empty for a spelling hint.")
                    .foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
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
