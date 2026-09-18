import SwiftData
import SwiftUI

private enum ControlCenterSection: String, CaseIterable, Identifiable {
    case history
    case memory
    case settings
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .history: "History"
        case .memory: "Memory"
        case .settings: "Settings"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .memory: "text.book.closed"
        case .settings: "gearshape"
        case .diagnostics: "ladybug"
        }
    }

    var isLibrary: Bool { self == .history || self == .memory }
}

@MainActor
struct MorieControlCenter: View {
    @ObservedObject var controller: AppController
    @Query(sort: \CaptureRecord.createdAt, order: .reverse) private var captures: [CaptureRecord]
    @State private var selection: ControlCenterSection? = .history
    @State private var selectedCaptureID: UUID?
    @State private var selectedMemory: MemorySelection?

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
                   let candidates = controller.memoryCandidates {
                    CaptureDetailView(
                        capture: capture,
                        captureID: id,
                        history: history,
                        memory: memory,
                        candidates: candidates,
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
                    switch selectedMemory {
                    case .memory(let id):
                        MemoryDetailView(store: memory, memoryID: id, onDelete: { self.selectedMemory = nil })
                    case .candidate(let id):
                        MemoryCandidateDetailView(store: memory, candidateID: id)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Memory",
                        systemImage: "text.book.closed",
                        description: Text("Keep the names and context that make future input sound like you.")
                    )
                }
            }
            .id(selectedMemory)
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
