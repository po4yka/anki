import SwiftUI

struct DetailRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSidebarItem {
            case .decks:
                DeckBrowserView()
            case .browse:
                SearchView()
            case .stats:
                StatisticsView()
            case .sync:
                SyncView()
        }
    }
}

#Preview {
    DetailRouter()
        .environment(AppState())
}
