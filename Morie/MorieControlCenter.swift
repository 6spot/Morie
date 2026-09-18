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
}

@MainActor
struct MorieControlCenter: View {
    @ObservedObject var controller: AppController

    @State private var selection: ControlCenterSection? = .history

    var body: some View {
        NavigationSplitView {
            List(ControlCenterSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Morie")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .history {
            case .history:
                if let history = controller.history, let memory = controller.memory {
                    CaptureHistoryView(
                        history: history,
                        memory: memory,
                        canStartCapture: controller.canStartCapture,
                        onRecord: controller.startCaptureOnly,
                        onRecognize: controller.recognizeHistoryCapture
                    )
                }
            case .memory:
                if let memory = controller.memory { MemoryView(store: memory) }
            case .settings:
                MorieSettingsView(controller: controller)
            case .diagnostics:
                DiagnosticLogView()
            }
        }
    }

}
