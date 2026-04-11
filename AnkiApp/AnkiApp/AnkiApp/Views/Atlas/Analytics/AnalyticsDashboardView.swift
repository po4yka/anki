import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct AnalyticsDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var model: AnalyticsModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(ContentUnavailableView(
                "Atlas Not Configured",
                systemImage: "chart.bar",
                description: Text("Configure Atlas in Settings to use Analytics.")
            ))
        }
        let analyticsModel = model ?? AnalyticsModel(atlas: atlas)
        return AnyView(DashboardTabView(model: analyticsModel)
            .onAppear {
                if model == nil {
                    model = analyticsModel
                    Task { await analyticsModel.loadTaxonomyTree() }
                }
            })
    }
}

private struct DashboardTabView: View {
    @State var model: AnalyticsModel

    var body: some View {
        TabView {
            TaxonomyTreeView(model: model)
                .tabItem { Label("Taxonomy", systemImage: "list.bullet.indent") }
            GapDetectionView(model: model)
                .tabItem { Label("Gaps", systemImage: "exclamationmark.triangle") }
            WeakNotesView(model: model)
                .tabItem { Label("Weak Notes", systemImage: "bolt.slash") }
            DuplicatesView(model: model)
                .tabItem { Label("Duplicates", systemImage: "doc.on.doc") }
        }
        .navigationTitle("Analytics")
    }
}
