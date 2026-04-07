import SwiftUI

struct DeckRowView: View {
    let node: Anki_Decks_DeckTreeNode
    let model: DeckBrowserModel
    @Environment(AppState.self) private var appState
    @State private var showingOverview = false
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirm = false
    @State private var showingDeckConfig = false
    @State private var showingCustomStudy = false
    @State private var renameName = ""

    var body: some View {
        HStack {
            Text(node.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            if node.newCount > 0 {
                Badge(count: Int(node.newCount), color: .blue)
            }
            if node.learnCount > 0 {
                Badge(count: Int(node.learnCount), color: .orange)
            }
            if node.reviewCount > 0 {
                Badge(count: Int(node.reviewCount), color: .green)
            }

            Button("Study") {
                showingOverview = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(node.newCount == 0 && node.learnCount == 0 && node.reviewCount == 0)
        }
        .contextMenu {
            Button("Rename...") {
                renameName = node.name
                showingRenameAlert = true
            }
            Button("Delete...", role: .destructive) {
                showingDeleteConfirm = true
            }
            Divider()
            Button("Custom Study...") {
                showingCustomStudy = true
            }
            Button("Options...") {
                showingDeckConfig = true
            }
        }
        .alert("Rename Deck", isPresented: $showingRenameAlert) {
            TextField("Deck Name", text: $renameName)
            Button("Rename") {
                let name = renameName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != node.name {
                    Task { await model.renameDeck(deckId: node.deckID, newName: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for \"\(node.name)\".")
        }
        .confirmationDialog("Delete \"\(node.name)\"?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteDeck(deckId: node.deckID) }
            }
        } message: {
            Text("This will delete the deck and all its cards. This action cannot be undone.")
        }
        .sheet(isPresented: $showingOverview) {
            DeckOverviewView(node: node, service: appState.service)
                .environment(appState)
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showingDeckConfig) {
            DeckConfigView(deckId: node.deckID, deckName: node.name, service: appState.service)
        }
        .sheet(isPresented: $showingCustomStudy) {
            CustomStudyView(service: appState.service, deckId: node.deckID)
        }
    }
}

private struct Badge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
