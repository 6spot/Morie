import SwiftData
import SwiftUI

enum MemorySelection: Hashable {
    case memory(UUID)
    case candidate(UUID)
}

struct MemoryView: View {
    @ObservedObject var store: MemoryStore
    @Binding var selection: MemorySelection?
    @Query private var captures: [CaptureRecord]
    @State private var search = ""
    @State private var status: MemoryStatus = .active
    @State private var editor: MemoryEditorMode?
    @State private var errorMessage: String?

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visibleEntries: [MemoryRecord] {
        store.entries.filter { entry in
            entry.status == status && (query.isEmpty || ([entry.name, entry.notes] + entry.aliases).contains {
                $0.localizedStandardContains(query)
            })
        }
    }

    private var visibleCandidates: [MemoryCandidate] {
        guard status == .active else { return [] }
        let inputs = Dictionary(uniqueKeysWithValues: captures.filter {
            $0.lifecycle != .capturing && $0.lifecycle != .cancelled && $0.refinement?.status != .running
        }.map { ($0.id, MemoryExtractionInput(capture: $0)) })
        return store.extractions.filter { extraction in
            guard let input = inputs[extraction.sourceCaptureID] else { return false }
            return input == extraction.input
        }.flatMap(\.candidates).filter { candidate in
            let draft = candidate.suggestion.draft
            return candidate.status == .pending && (query.isEmpty || ([draft.name, draft.notes] + draft.aliases).contains {
                $0.localizedStandardContains(query)
            })
        }
    }

    private var visibleSelections: [MemorySelection] {
        visibleCandidates.map { .candidate($0.id) } + visibleEntries.map { .memory($0.id) }
    }

    var body: some View {
        List(selection: $selection) {
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle") }
            if !visibleCandidates.isEmpty {
                Section("Suggestions to Review") {
                    ForEach(visibleCandidates) { candidate in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(candidate.suggestion.draft.name, systemImage: "sparkles")
                                .lineLimit(2)
                            Text(candidate.suggestion.draft.kind.title + " · Not saved yet")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(candidate.suggestion.evidence)
                                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 6)
                        .tag(MemorySelection.candidate(candidate.id))
                    }
                }
            }
            if !visibleEntries.isEmpty {
                Section("\(status.title) Memories") {
                    ForEach(visibleEntries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(entry.name, systemImage: entry.kind?.systemImage ?? "bookmark")
                                .lineLimit(2)
                            Text(entry.kind?.title ?? "Memory").font(.caption).foregroundStyle(.secondary)
                            if !entry.notes.isEmpty {
                                Text(entry.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .padding(.vertical, 6)
                        .tag(MemorySelection.memory(entry.id))
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if visibleSelections.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Label(query.isEmpty ? "No \(status.title) Memories" : "No Matching Memories", systemImage: "text.book.closed")
                } description: {
                    Text(query.isEmpty ? "Save names and projects to make future input more accurate." : "Try another search or filter.")
                } actions: {
                    if query.isEmpty && status == .active {
                        Button("New Memory", systemImage: "plus") { editor = .create(sourceCaptureID: nil) }
                    } else {
                        Button("Show Active Memories") { search = ""; status = .active }
                    }
                }
            }
        }
        .navigationTitle("Memory")
        .navigationSubtitle("\(visibleEntries.count) memories")
        .searchable(text: $search, prompt: "Search memories")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Filter Memories", systemImage: "line.3.horizontal.decrease") {
                    Picker("Status", selection: $status) {
                        ForEach(MemoryStatus.allCases) { Text($0.title).tag($0) }
                    }
                }
                .help("\(status.title) memories")
                Button("New Memory", systemImage: "plus") { editor = .create(sourceCaptureID: nil) }
            }
        }
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
        .onChange(of: visibleSelections, initial: true) { _, ids in
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
                        Label(memory.userConfirmed ? "Confirmed by you" : "Not confirmed",
                              systemImage: memory.userConfirmed ? "checkmark.seal" : "questionmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    if !memory.aliases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Also Recognized As").font(.headline)
                            Text(memory.aliases.joined(separator: ", ")).textSelection(.enabled)
                        }
                    }
                    if !memory.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Context").font(.headline)
                            Text(memory.notes).lineSpacing(5).textSelection(.enabled)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Status", value: memory.status?.title ?? "Unavailable")
                            Text(memory.status == .active && memory.userConfirmed
                                 ? "Morie can use this memory to correct confirmed names in future input."
                                 : "This memory is kept for reference and is not used to refine input.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Personalization", systemImage: "text.bubble")
                    }

                    DisclosureGroup("Sources & History") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let candidateID = memory.sourceCandidateID,
                               let extraction = store.extractions.first(where: { $0.candidates.contains(where: { $0.id == candidateID }) }) {
                                Text("Saved from a suggestion you reviewed.").foregroundStyle(.secondary)
                                MemoryExtractionSource(extraction: extraction)
                            }
                            if memory.sourceCaptureIDs.isEmpty {
                                Text("Added manually").foregroundStyle(.secondary)
                            }
                            ForEach(Array(memory.sourceCaptureIDs.enumerated()), id: \.element) { index, id in
                                NavigationLink("Source Capture \(index + 1)") {
                                    ManagementDetailContent { CaptureMemorySource(captureID: id) }
                                        .navigationTitle("Source Capture")
                                }
                            }
                            if let previousID = memory.supersedesID {
                                NavigationLink("Previous Memory") { MemoryDetailView(store: store, memoryID: previousID) }
                            }
                            if let replacement = store.entries.first(where: { $0.supersedesID == memory.id }) {
                                NavigationLink("Replacement: \(replacement.name)") {
                                    MemoryDetailView(store: store, memoryID: replacement.id)
                                }
                            }
                            LabeledContent("Created", value: memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Updated", value: memory.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    }
                }
                .navigationTitle("Memory")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Edit Memory", systemImage: "pencil") { editor = .edit(memoryID) }
                            .disabled(memory.status == .superseded)
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
                ContentUnavailableView("Memory No Longer Available", systemImage: "bookmark")
            }
        }
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .confirmationDialog("Delete this memory?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Memory", role: .destructive) {
                perform {
                    try store.delete(memoryID)
                    if let onDelete { onDelete() } else { dismiss() }
                }
            }
        } message: {
            Text("This memory will be permanently deleted. Source captures are kept.")
        }
        .alert("Couldn’t Update Memory", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

enum MemoryEditorMode: Identifiable {
    case create(sourceCaptureID: UUID?)
    case edit(UUID)
    case replace(UUID)
    case reviewCandidate(UUID)

    var id: String {
        switch self {
        case .create(let source): "create-\(source?.uuidString ?? "manual")"
        case .edit(let id): "edit-\(id)"
        case .replace(let id): "replace-\(id)"
        case .reviewCandidate(let id): "review-\(id)"
        }
    }

    var title: String {
        switch self {
        case .create: "Save Memory"
        case .edit: "Edit Memory"
        case .replace: "Replace Memory"
        case .reviewCandidate: "Review Memory Candidate"
        }
    }
}

struct MemoryEditorSheet: View {
    @ObservedObject var store: MemoryStore
    let mode: MemoryEditorMode
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MemoryDraft()
    @State private var aliases = ""
    @State private var existingID: UUID?
    @State private var errorMessage: String?
    @State private var candidateExtraction: MemoryExtractionRecord?
    @State private var candidate: MemoryCandidate?
    @State private var candidateIsCurrent = false

    private var canChooseExisting: Bool {
        switch mode {
        case .create(let sourceID): sourceID != nil
        case .reviewCandidate: true
        default: false
        }
    }

    private var canSave: Bool {
        if case .reviewCandidate = mode { return candidateIsCurrent && candidate?.status == .pending }
        return true
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(mode.title).font(.headline)
            Form {
                if case .create(let sourceID) = mode, let sourceID {
                    Section("From Capture") { CaptureMemorySource(captureID: sourceID).lineLimit(5) }
                }
                if let candidateExtraction, let candidate {
                    Section("Source Evidence") {
                        Text(candidate.suggestion.evidence).textSelection(.enabled)
                        MemoryExtractionSource(extraction: candidateExtraction)
                        Text("Review the name, aliases and notes before saving. AI suggestions can be inaccurate.")
                            .foregroundStyle(.secondary)
                    }
                }
                if canChooseExisting {
                    Picker("Save to", selection: $existingID) {
                        Text("New Memory").tag(nil as UUID?)
                        ForEach(store.entries.filter { $0.status == .active }) {
                            Text("\($0.name) (\($0.kind?.title ?? "Memory"))").tag(Optional($0.id))
                        }
                    }
                }
                if existingID == nil {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(MemoryKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Name", text: $draft.name)
                    LabeledContent("Aliases (one per line)") {
                        TextEditor(text: $aliases)
                            .multilineTextAlignment(.leading)
                            .frame(height: 64)
                            .accessibilityLabel("Aliases, one per line")
                    }
                    LabeledContent("Notes") {
                        TextEditor(text: $draft.notes)
                            .multilineTextAlignment(.leading)
                            .frame(height: 96)
                            .accessibilityLabel("Memory notes")
                    }
                } else {
                    Text("This capture will be linked as another source. The memory's name and notes will be kept.")
                        .foregroundStyle(.secondary)
                }
                if case .replace = mode {
                    Text("The new memory becomes active. The previous memory stays available as superseded and stops appearing in relevant context.")
                        .foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            HStack {
                if case .reviewCandidate(let id) = mode, candidate?.status == .pending {
                    Button("Dismiss Suggestion") {
                        do { try store.dismissCandidate(id); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 580)
        .frame(minHeight: 500, idealHeight: 640, maxHeight: 760)
        .onAppear {
            do {
                try store.load()
                switch mode {
                case .create: break
                case .edit(let id), .replace(let id):
                    guard let saved = try store.memory(id).draft else { throw MemoryStore.StoreError.memoryUnavailable }
                    draft = saved
                    aliases = saved.aliases.joined(separator: "\n")
                case .reviewCandidate(let id):
                    let result = try store.candidate(id)
                    candidateExtraction = result.extraction
                    candidate = result.candidate
                    draft = result.candidate.suggestion.draft
                    aliases = draft.aliases.joined(separator: "\n")
                    candidateIsCurrent = store.isCurrent(result.extraction)
                    if !candidateIsCurrent { throw MemoryStore.StoreError.sourceChanged }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        draft.aliases = aliases.split(whereSeparator: \.isNewline).map(String.init)
        do {
            switch mode {
            case .create(let sourceID):
                if let existingID, let sourceID { try store.addSource(sourceID, to: existingID) }
                else { try store.create(draft, sourceCaptureID: sourceID) }
            case .edit(let id): try store.update(id, draft: draft)
            case .replace(let id): try store.replace(id, with: draft)
            case .reviewCandidate(let id): try store.acceptCandidate(id, draft: draft, existingMemoryID: existingID)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct CaptureMemorySection: View {
    @ObservedObject var store: MemoryStore
    let capture: CaptureRecord
    @State private var editor: MemoryEditorMode?
    @State private var errorMessage: String?

    private var linked: [MemoryRecord] { store.entries.filter { $0.sourceCaptureIDs.contains(capture.id) } }
    private var related: [MemoryContextMatch] {
        guard capture.lifecycle != .capturing else { return [] }
        let text = capture.finalText.isEmpty ? capture.recognizedText : capture.finalText
        return MemoryContextRetriever.retrieve(for: text, from: store.entries.compactMap(\.snapshot))
            .filter { match in !linked.contains(where: { $0.id == match.id }) }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Button("Save Memory…", systemImage: "bookmark") { editor = .create(sourceCaptureID: capture.id) }
                    .disabled(capture.lifecycle == .capturing || capture.refinement?.status == .running
                              || (capture.recognizedText + capture.finalText).isEmpty)
                ForEach(linked) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(entry.name) {
                            MemoryDetailView(store: store, memoryID: entry.id)
                        }
                        .buttonStyle(.link)
                        Text("Saved from this capture · \(entry.status?.title ?? "Unavailable")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(related) { match in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(match.memory.name) {
                            MemoryDetailView(store: store, memoryID: match.id)
                        }
                        .buttonStyle(.link)
                        Text("Related · \(match.matchedTerm)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Memory", systemImage: "text.book.closed")
        }
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .onAppear {
            do { try store.load(); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct CaptureMemorySource: View {
    @Query private var captures: [CaptureRecord]

    init(captureID: UUID) {
        _captures = Query(filter: #Predicate<CaptureRecord> { $0.id == captureID })
    }

    var body: some View {
        if let capture = captures.first {
            LabeledContent("Captured", value: capture.createdAt.formatted())
            if let app = capture.sourceApplicationName { LabeledContent("Source App", value: app) }
            Text(capture.finalText.isEmpty ? capture.recognizedText : capture.finalText).textSelection(.enabled)
        } else {
            Text("The source capture was deleted. The memory you saved separately is still available.")
                .foregroundStyle(.secondary)
        }
    }
}
