import SwiftUI

@main
struct AnkiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Note") {
                    // TODO: open add-note window
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Navigate") {
                Button("Decks") {
                    appState.selectedSidebarItem = .decks
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Browse") {
                    appState.selectedSidebarItem = .browse
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Statistics") {
                    appState.selectedSidebarItem = .stats
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandMenu("Study") {
                Button("Start Review") {
                    // TODO: start review for current deck
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Sync") {
                    appState.selectedSidebarItem = .sync
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
