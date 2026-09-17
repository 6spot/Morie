import SwiftUI

private enum ControlCenterSection: String, CaseIterable, Identifiable {
    case history
    case settings
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .history: "History"
        case .settings: "Settings"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .diagnostics: "ladybug"
        }
    }
}

@MainActor
struct MorieControlCenter: View {
    @ObservedObject var controller: AppController
    let captureStore: CaptureStore?

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
                history
            case .settings:
                MorieSettingsView(controller: controller)
            case .diagnostics:
                DiagnosticLogView()
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        if let captureStore {
            CaptureHistoryView()
                .modelContainer(captureStore.container)
        } else {
            ContentUnavailableView(
                "History Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Morie could not open Capture storage.")
            )
            .navigationTitle("History")
        }
    }
}
