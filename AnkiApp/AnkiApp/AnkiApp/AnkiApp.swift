import SwiftUI

@main
struct AnkiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
