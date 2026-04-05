import SwiftUI

struct DeckBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var model: DeckBrowserModel?
    @State private var showingReviewer = false

    var body: some View {
        Group {
            if let model {
                List {
                    ForEach(model.deckTree?.children ?? [], id: \.deckID) { node in
                        DeckNodeView(node: node, model: model)
                    }
                }
                .navigationTitle("Decks")
                .toolbar {
                    ToolbarItem {
                        Button("Add Note") {
                            // TODO: open add-note window
                        }
                    }
                }
                .sheet(isPresented: $showingReviewer) {
                    ReviewerView()
                        .environment(appState)
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
