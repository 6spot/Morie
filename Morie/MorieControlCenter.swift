import SwiftData
import SwiftUI

private enum ControlCenterSection: String, CaseIterable, Identifiable {
    case history
    case memory
    case dictionary
    case settings
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .history: "History"
        case .memory: "Personal Memory"
        case .dictionary: "Dictionary"
        case .settings: "Settings"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .memory: "person.text.rectangle"
        case .dictionary: "character.book.closed"
        case .settings: "gearshape"
        case .diagnostics: "ladybug"
        }
    }

    var isLibrary: Bool { self == .history || self == .memory || self == .dictionary }
}

@MainActor
struct MorieControlCenter: View {
    @ObservedObject var controller: AppController
    @Query(sort: \CaptureRecord.createdAt, order: .reverse) private var captures: [CaptureRecord]
    @State private var selection: ControlCenterSection? = .history
    @State private var selectedCaptureID: UUID?
    @State private var selectedMemory: UUID?
    @State private var selectedDictionaryEntry: UUID?

    var body: some View {
        Group {
            if (selection ?? .history).isLibrary {
                NavigationSplitView {
                    sidebar
                } content: {
                    libraryList
                        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
                } detail: {
                    libraryDetail
                        .navigationSplitViewColumnWidth(min: 420, ideal: 600)
                }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    switch selection {
                    case .settings:
                        MorieSettingsView(controller: controller)
                    case .diagnostics:
                        DiagnosticLogView()
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                sidebarItem(.history)
                sidebarItem(.dictionary)
                sidebarItem(.memory)
            }
            Section("App") {
                sidebarItem(.settings)
                sidebarItem(.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Morie")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
    }

    private func sidebarItem(_ section: ControlCenterSection) -> some View {
        Label(section.title, systemImage: section.systemImage).tag(section)
    }

    @ViewBuilder
    private var libraryList: some View {
        switch selection ?? .history {
        case .history:
            CaptureHistoryView(
                captures: captures,
                selection: $selectedCaptureID,
                canStartCapture: controller.canStartCapture,
                onRecord: controller.startCaptureOnly
            )
        case .dictionary:
            if let dictionary = controller.dictionary {
                DictionaryView(store: dictionary, selection: $selectedDictionaryEntry)
            }
        case .memory:
            if let memory = controller.memory {
                MemoryView(store: memory, selection: $selectedMemory)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var libraryDetail: some View {
        switch selection ?? .history {
        case .history:
            NavigationStack {
                if let id = selectedCaptureID,
                   let capture = captures.first(where: { $0.id == id }),
                   let history = controller.history,
                   let memory = controller.memory,
                   let learning = controller.memoryLearning {
                    CaptureDetailView(
                        capture: capture,
                        captureID: id,
                        history: history,
                        memory: memory,
                        learning: learning,
                        canRecognize: controller.canStartCapture,
                        onRecognize: controller.recognizeHistoryCapture
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Capture",
                        systemImage: "waveform",
                        description: Text("Your saved words, recordings and memories appear here.")
                    )
                }
            }
            .id(selectedCaptureID)
        case .memory:
            NavigationStack {
                if let memory = controller.memory, let selectedMemory {
                    MemoryDetailView(store: memory, memoryID: selectedMemory, onDelete: { self.selectedMemory = nil })
                } else {
                    ContentUnavailableView(
                        "Select a Memory",
                        systemImage: "text.book.closed",
                        description: Text("Personal information learned from your everyday input appears here.")
                    )
                }
            }
            .id(selectedMemory)
        case .dictionary:
            NavigationStack {
                if let dictionary = controller.dictionary, let id = selectedDictionaryEntry {
                    DictionaryDetailView(store: dictionary, entryID: id, onDelete: { selectedDictionaryEntry = nil })
                } else {
                    ContentUnavailableView("Select a Word", systemImage: "character.book.closed",
                                           description: Text("Your names, products and technical terms."))
                }
            }
            .id(selectedDictionaryEntry)
        default:
            EmptyView()
        }
    }
}

/// A reading surface shared by Capture and Memory details. Controls stay native.
struct ManagementDetailContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
