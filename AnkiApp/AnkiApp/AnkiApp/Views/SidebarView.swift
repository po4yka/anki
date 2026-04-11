import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case decks = "Decks"
    case browse = "Browse"
    case notetypes = "Note Types"
    case imageOcclusion = "Image Occlusion"
    case stats = "Statistics"
    case importPkg = "Import"
    case exportPkg = "Export"
    case sync = "Sync"
    case atlasSearch = "Search+"
    case analytics = "Analytics"
    case knowledgeGraph = "Knowledge Graph"
    case generator = "Generator"
    case obsidian = "Obsidian"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
            case .decks: "rectangle.stack"
            case .browse: "magnifyingglass"
            case .notetypes: "doc.on.doc"
            case .imageOcclusion: "photo.on.rectangle"
            case .stats: "chart.bar"
            case .importPkg: "square.and.arrow.down"
            case .exportPkg: "square.and.arrow.up"
            case .sync: "arrow.triangle.2.circlepath"
            case .atlasSearch: "sparkle.magnifyingglass"
            case .analytics: "brain.head.profile"
            case .knowledgeGraph: "point.3.connected.trianglepath.dotted"
            case .generator: "wand.and.stars"
            case .obsidian: "doc.text.magnifyingglass"
        }
    }

    var isAtlas: Bool {
        switch self {
            case .atlasSearch, .analytics, .knowledgeGraph, .generator, .obsidian: true
            default: false
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    private let ankiItems: [SidebarItem] = [
        .decks,
        .browse,
        .notetypes,
        .imageOcclusion,
        .stats,
        .importPkg,
        .exportPkg,
        .sync
    ]
    private let atlasItems: [SidebarItem] = [.atlasSearch, .analytics, .knowledgeGraph, .generator, .obsidian]

    var body: some View {
        @Bindable var appState = appState
        List {
#if os(macOS)
            Section("Anki") {
                ForEach(ankiItems) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            Section("Atlas") {
                ForEach(atlasItems) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
#else
            Section("Anki") {
                ForEach(ankiItems) { item in
                    Button {
                        appState.selectedSidebarItem = item
                    } label: {
                        Label(item.rawValue, systemImage: item.systemImage)
                    }
                }
            }
            Section("Atlas") {
                ForEach(atlasItems) { item in
                    Button {
                        appState.selectedSidebarItem = item
                    } label: {
                        Label(item.rawValue, systemImage: item.systemImage)
                    }
                }
            }
#endif
        }
        .navigationTitle("Anki")
        .listStyle(.sidebar)
        .animation(.default, value: appState.selectedSidebarItem)
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
