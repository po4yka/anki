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
            CommandGroup(replacing: .undoRedo) {
                Button(appState.undoStatus?.undo.isEmpty == false
                    ? "Undo \(appState.undoStatus?.undo ?? "")" : "Undo") {
                        Task {
                            do {
                                _ = try await appState.service.undo()
                                await appState.refreshUndoStatus()
                            } catch {}
                        }
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(appState.undoStatus?.undo.isEmpty ?? true)

                Button(appState.undoStatus?.redo.isEmpty == false
                    ? "Redo \(appState.undoStatus?.redo ?? "")" : "Redo") {
                        Task {
                            do {
                                _ = try await appState.service.redo()
                                await appState.refreshUndoStatus()
                            } catch {}
                        }
                    }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(appState.undoStatus?.redo.isEmpty ?? true)
            }

            CommandGroup(after: .newItem) {
                Button("Add Note") {
                    // Open add-note window (not yet implemented)
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
                    // Start review for current deck (not yet implemented)
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
