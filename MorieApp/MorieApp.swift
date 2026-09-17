import SwiftUI

@main
struct MorieApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
                .task {
                    await model.start()
                }
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Morie")
        }
        .menuBarExtraStyle(.window)
    }
}
