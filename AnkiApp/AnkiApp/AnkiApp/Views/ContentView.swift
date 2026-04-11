import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Group {
            #if os(macOS)
            macContent
            #else
            iosContent
            #endif
        }
        .sheet(item: Binding(
            get: { appState.navigation.presentedSheet },
            set: { appState.navigation.presentedSheet = $0 }
        )) { sheet in
            switch sheet {
                case .addNote:
                    NavigationStack {
                        NoteEditorView()
                            .environment(appState)
                    }
                case .reviewer:
                    ReviewerView()
                        .environment(appState)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $appState.isShowingPreferencesSheet) {
            NavigationStack {
                PreferencesView()
                    .environment(appState)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                appState.isShowingPreferencesSheet = false
                            }
                        }
                    }
            }
        }
        #endif
        .ankiErrorAlert($appState.error)
    }

    private var macContent: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            DetailRouter()
        }
    }

    private var iosContent: some View {
        TabView(selection: Binding(
            get: { appState.selectedMobileTab },
            set: { appState.selectedMobileTab = $0 }
        )) {
            NavigationStack {
                DeckBrowserView()
            }
            .tabItem {
                Label(MobileTab.decks.rawValue, systemImage: MobileTab.decks.systemImage)
            }
            .tag(MobileTab.decks)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label(MobileTab.browse.rawValue, systemImage: MobileTab.browse.systemImage)
            }
            .tag(MobileTab.browse)

            NavigationStack {
                StatisticsView()
            }
            .tabItem {
                Label(MobileTab.stats.rawValue, systemImage: MobileTab.stats.systemImage)
            }
            .tag(MobileTab.stats)

            NavigationStack {
                SyncView()
            }
            .tabItem {
                Label(MobileTab.sync.rawValue, systemImage: MobileTab.sync.systemImage)
            }
            .tag(MobileTab.sync)

            NavigationStack {
                MobileMoreView()
            }
            .tabItem {
                Label(MobileTab.more.rawValue, systemImage: MobileTab.more.systemImage)
            }
            .tag(MobileTab.more)
        }
    }
}

private struct MobileMoreView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Editing") {
                NavigationLink("Note Types") {
                    NotetypeListView()
                }
                NavigationLink("Image Occlusion") {
                    ImageOcclusionView()
                }
            }

            Section("Import / Export") {
                NavigationLink("Import Package") {
                    ImportView()
                }
                NavigationLink("Import CSV") {
                    CsvImportView()
                }
                NavigationLink("Export Package") {
                    ExportView()
                }
            }

            Section("Settings") {
                Button("Preferences") {
                    appState.isShowingPreferencesSheet = true
                }
            }

            if appState.isAtlasAvailable {
                Section("Atlas") {
                    NavigationLink("Search+") {
                        AtlasSearchView()
                    }
                    NavigationLink("Analytics") {
                        AnalyticsDashboardView()
                    }
                    NavigationLink("Knowledge Graph") {
                        KnowledgeGraphView()
                    }
                    NavigationLink("Generator") {
                        CardGeneratorView()
                    }
                    NavigationLink("Obsidian") {
                        VaultBrowserView()
                    }
                }
            }
        }
        .navigationTitle("More")
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
