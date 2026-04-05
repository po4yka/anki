import SwiftUI

struct DeckRowView: View {
    let node: DeckTreeNode
    let model: DeckBrowserModel
    @Environment(AppState.self) private var appState
    @State private var showingReviewer = false

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
                appState.selectedDeckId = node.deckId
                showingReviewer = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(node.newCount == 0 && node.learnCount == 0 && node.reviewCount == 0)
        }
        .sheet(isPresented: $showingReviewer) {
            ReviewerView(deckId: node.deckId)
                .environment(appState)
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
