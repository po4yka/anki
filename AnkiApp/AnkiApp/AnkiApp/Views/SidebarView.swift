import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case decks = "Decks"
    case browse = "Browse"
    case stats = "Statistics"
    case sync = "Sync"
    case atlasSearch = "Smart Search"
    case analytics = "Analytics"
    case generator = "Card Generator"
    case obsidian = "Obsidian"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .decks: "rectangle.stack"
        case .browse: "magnifyingglass"
        case .stats: "chart.bar"
        case .sync: "arrow.triangle.2.circlepath"
        case .atlasSearch: "sparkle.magnifyingglass"
        case .analytics: "brain.head.profile"
        case .generator: "wand.and.stars"
        case .obsidian: "doc.text.magnifyingglass"
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
