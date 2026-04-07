import SwiftUI

struct DetailRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSidebarItem {
            case .decks:
                DeckBrowserView()
            case .browse:
                SearchView()
            case .notetypes:
                NotetypeListView()
            case .imageOcclusion:
                ImageOcclusionView()
            case .stats:
                StatisticsView()
            case .importPkg:
                ImportView()
            case .exportPkg:
                ExportView()
            case .sync:
                SyncView()
            case .atlasSearch:
                AtlasSearchView()
            case .analytics:
                AnalyticsDashboardView()
            case .generator:
                CardGeneratorView()
            case .obsidian:
                VaultBrowserView()
        }
    }
}

#Preview {
    DetailRouter()
        .environment(AppState())
}
