import SwiftUI

@main
struct AnkiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .sheet(isPresented: Binding(
                    get: { appState.isShowingAddNote },
                    set: { appState.isShowingAddNote = $0 }
                )) {
                    NavigationStack {
                        NoteEditorView()
                            .environment(appState)
                    }
                    .frame(minWidth: 500, minHeight: 400)
                }
                .sheet(isPresented: Binding(
                    get: { appState.isShowingReviewer },
                    set: { appState.isShowingReviewer = $0 }
                )) {
                    ReviewerView()
                        .environment(appState)
                        .frame(minWidth: 600, minHeight: 500)
                }
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
                    appState.presentAddNote()
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
                    Task { await appState.startReview() }
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
