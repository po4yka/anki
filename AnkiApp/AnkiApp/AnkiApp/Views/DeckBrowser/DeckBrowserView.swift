import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct DeckBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var model: DeckBrowserModel?
    @State private var showingNewDeckAlert = false
    @State private var newDeckName = ""

    var body: some View {
        Group {
            if let model {
                if model.isLoading {
                    ProgressView("Loading decks...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.default, value: model.isLoading)
                } else if !appState.isCollectionOpen {
                    ContentUnavailableView {
                        Label("No Collection Open", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Open a collection from Preferences to get started.")
                    } actions: {
                        Button("Open Preferences") {
                            appState.showPreferences()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if model.deckTree?.children.isEmpty ?? true {
                    ContentUnavailableView(
                        "No Decks",
                        systemImage: "rectangle.stack",
                        description: Text("Create a deck to get started.")
                    )
                } else {
                    List {
                        ForEach(model.deckTree?.children ?? [], id: \.deckID) { node in
                            DeckNodeView(node: node, model: model)
                        }
                    }
                    .navigationTitle("Decks")
                    .toolbar {
                        ToolbarItem {
                            Button("New Deck") {
                                newDeckName = ""
                                showingNewDeckAlert = true
                            }
                            .keyboardShortcut("d", modifiers: [.command, .shift])
                        }
                        ToolbarItem {
                            Button("Add Note") {
                                appState.presentAddNote()
                            }
                            .keyboardShortcut("n", modifiers: .command)
                        }
                    }
                    .alert("New Deck", isPresented: $showingNewDeckAlert) {
                        TextField("Deck Name", text: $newDeckName)
                        Button("Create") {
                            let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                Task { await model.createDeck(name: name) }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Enter a name for the new deck.")
                    }
                }
            } else {
                ProgressView("Loading decks...")
            }
        }
        .onAppear {
            if model == nil {
                model = DeckBrowserModel(service: appState.service)
                Task { await model?.load() }
            }
        }
        .ankiErrorAlert(Binding(
            get: { model?.error },
            set: { model?.error = $0 }
        ))
    }
}

private struct DeckNodeView: View {
    let node: Anki_Decks_DeckTreeNode
    let model: DeckBrowserModel

    var body: some View {
        if node.children.isEmpty {
            DeckRowView(node: node, model: model)
        } else {
            DisclosureGroup {
                ForEach(node.children, id: \.deckID) { child in
                    DeckNodeView(node: child, model: model)
                }
            } label: {
                DeckRowView(node: node, model: model)
            }
        }
    }
}

#Preview {
    DeckBrowserView()
        .environment(AppState())
}
