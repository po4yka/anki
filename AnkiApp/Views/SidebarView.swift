import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case decks = "Decks"
    case browse = "Browse"
    case stats = "Statistics"
    case sync = "Sync"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
            case .decks: "rectangle.stack"
            case .browse: "magnifyingglass"
            case .stats: "chart.bar"
            case .sync: "arrow.triangle.2.circlepath"
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        List(SidebarItem.allCases, selection: $appState.selectedSidebarItem) { item in
            Label(item.rawValue, systemImage: item.systemImage)
                .tag(item)
        }
        .navigationTitle("Anki")
        .listStyle(.sidebar)
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
