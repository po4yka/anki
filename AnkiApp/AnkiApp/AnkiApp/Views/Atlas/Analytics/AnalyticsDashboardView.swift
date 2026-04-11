import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct AnalyticsDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var model: AnalyticsModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(AtlasUnavailableView(featureName: "Analytics", systemImage: "chart.bar"))
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
