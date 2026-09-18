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
                    Text(entry.kind?.title ?? "Memory").font(.caption).foregroundStyle(.secondary)
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
                    Label(search.isEmpty ? "No \(status.title) Memories" : "No Matching Memories", systemImage: "person.text.rectangle")
                } description: {
                    Text(search.isEmpty ? "Morie learns about your projects, relationships and preferences from everyday voice input. Memories appear here automatically." : "Try another search or filter.")
                }
            }
        }
        .navigationTitle("Personal Memory")
        .navigationSubtitle(visibleEntries.count == 1 ? "1 memory" : "\(visibleEntries.count) memories")
        .searchable(text: $search, prompt: "Search personal memories")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Filter Memories", systemImage: "line.3.horizontal.decrease") {
                    Picker("Status", selection: $status) { ForEach(MemoryStatus.allCases) { Text($0.title).tag($0) } }
                }
                Button("New Memory", systemImage: "plus") { editor = .create }
            }
        }
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = "Could not load personal memories." }
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
                        Label(memory.kind?.title ?? "Memory", systemImage: memory.kind?.systemImage ?? "bookmark")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(memory.name).font(.title).textSelection(.enabled)
                        Label(memory.origin?.title ?? "Personal Memory", systemImage: memory.origin == .automatic ? "sparkles" : "pencil")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(memory.notes).lineSpacing(5).textSelection(.enabled)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Status", value: memory.status?.title ?? "Unavailable")
                            Text(memory.status == .active
                                 ? "Helps Morie understand future input while preserving what you say."
                                 : "Kept for reference; excluded from future input context.")
                                .foregroundStyle(.secondary)
                            if memory.origin == .user {
                                Text("Your edits take precedence over automatic updates.").foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Label("Used in Input", systemImage: "text.bubble") }
                    DisclosureGroup("Sources & History") {
                        VStack(alignment: .leading, spacing: 12) {
                            if memory.sourceCaptureIDs.isEmpty { Text("Added by you").foregroundStyle(.secondary) }
                            ForEach(Array(memory.sourceCaptureIDs.enumerated()), id: \.element) { index, id in
                                NavigationLink("Source Input \(index + 1)") {
                                    ManagementDetailContent {
                                        CaptureMemorySource(captureID: id)
                                        ForEach(store.analyses.filter { $0.sourceCaptureID == id && $0.observations.contains(where: { $0.memoryID == memoryID }) }) { analysis in
                                            MemoryAnalysisSourceView(analysis: analysis)
                                        }
                                    }
                                    .navigationTitle("Memory Source")
                                }
                            }
                            if let previousID = memory.supersedesID {
                                NavigationLink("Previous Memory") { MemoryDetailView(store: store, memoryID: previousID) }
                            }
                            if let replacement = store.entries.first(where: { $0.supersedesID == memory.id }) {
                                NavigationLink("Updated Memory") { MemoryDetailView(store: store, memoryID: replacement.id) }
                            }
                            LabeledContent("Created", value: memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Updated", value: memory.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Edit Memory", systemImage: "pencil") { editor = .edit(memoryID) }.disabled(memory.status == .superseded)
                        Menu("Memory Actions", systemImage: "ellipsis") {
                            if memory.status == .active {
                                Button("Archive Memory", systemImage: "archivebox") { perform { try store.archive(memoryID) } }
                            } else if memory.status == .archived {
                                Button("Restore Memory", systemImage: "arrow.uturn.backward") { perform { try store.restore(memoryID) } }
                            }
                            if memory.status != .superseded {
                                Button("Replace Memory…", systemImage: "arrow.triangle.2.circlepath") { editor = .replace(memoryID) }
                            }
                            Divider()
                            Button("Delete Memory…", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Memory No Longer Available", systemImage: "person.text.rectangle")
            }
        }
        .navigationTitle("Personal Memory")
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .confirmationDialog("Delete this memory?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Memory", role: .destructive) {
                perform { try store.delete(memoryID); if let onDelete { onDelete() } else { dismiss() } }
            }
        } message: {
            Text("The memory will be deleted and excluded from automatic learning. Source inputs are kept. You can add this topic again yourself.")
        }
        .alert("Couldn’t Update Memory", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
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
        case .create: "New Personal Memory"
        case .edit: "Edit Personal Memory"
        case .replace: "Replace Personal Memory"
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
                Picker("Type", selection: $draft.kind) { ForEach(MemoryKind.allCases) { Text($0.title).tag($0) } }
                TextField("Topic", text: $draft.name)
                LabeledContent("Personal Information") {
                    TextEditor(text: $draft.notes).frame(height: 140).accessibilityLabel("Personal information")
                }
                Text("Save projects, relationships and preferences here. Use Dictionary for word spellings.").foregroundStyle(.secondary)
                if case .replace = mode { Text("The previous memory stays available as superseded.").foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
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
            LabeledContent("Captured", value: capture.createdAt.formatted())
            if let app = capture.sourceApplicationName { LabeledContent("Source App", value: app) }
            Text(capture.finalText).textSelection(.enabled)
        } else {
            Text("The source input was deleted. The separately saved memory remains available.").foregroundStyle(.secondary)
        }
    }
}
