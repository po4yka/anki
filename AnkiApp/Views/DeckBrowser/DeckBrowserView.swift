import SwiftUI

struct DeckBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var model: DeckBrowserModel?
    @State private var showingReviewer = false

    var body: some View {
        Group {
            if let model {
                List {
                    ForEach(model.deckTree) { node in
                        DeckNodeView(node: node, model: model)
                    }
                }
                .navigationTitle("Decks")
                .toolbar {
                    ToolbarItem {
                        Button("Add Note") {
                            // Open add-note window
                            NSApp.sendAction(#selector(AppDelegate.openAddNote(_:)), to: nil, from: nil)
                        }
                    }
                }
                .sheet(isPresented: $showingReviewer) {
                    if let deckId = appState.selectedDeckId {
                        ReviewerView(deckId: deckId)
                            .environment(appState)
                    }
                }
            } else {
                ProgressView("Loading decks...")
            }
        }
        .onAppear {
            if model == nil {
                model = DeckBrowserModel(service: appState.service)
                Task { await model?.loadDecks() }
            }
        }
        .ankiErrorAlert($model?.error)
    }
}

private struct DeckNodeView: View {
    let node: DeckTreeNode
    let model: DeckBrowserModel

    var body: some View {
        if node.children.isEmpty {
            DeckRowView(node: node, model: model)
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
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
