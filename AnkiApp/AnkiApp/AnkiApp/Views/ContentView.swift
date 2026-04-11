import SwiftUI
import AppleBridgeCore
import AppleSharedUI

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
        Group {
            if appState.requiresBackendIntegration {
                IOSRemoteBackendOnboardingView()
            } else {
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
    }
}

private struct IOSRemoteBackendOnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        guard let connectionStore = appState.connectionStore else {
            return AnyView(
                ContentUnavailableView(
                    "Remote Backend Unavailable",
                    systemImage: "wifi.slash",
                    description: Text("The app could not create a remote backend connection store.")
                )
            )
        }

        return AnyView(content(connectionStore: connectionStore))
    }

    @ViewBuilder
    private func content(connectionStore: BackendConnectionStore) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContentUnavailableView(
                        appState.backendStatusTitle,
                        systemImage: "iphone.and.arrow.forward",
                        description: Text(appState.backendStatusMessage)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connection")
                            .font(.headline)
                        TextField("Backend URL", text: Bindable(connectionStore).endpointURLString)
                            .textFieldStyle(.roundedBorder)
                            .remoteBackendURLFieldStyle()

                        Picker("Deployment", selection: Bindable(connectionStore).deploymentKind) {
                            ForEach(BackendDeploymentKind.allCases, id: \.self) { kind in
                                Text(kind.rawValue.capitalized).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Button("Save Endpoint") {
                                Task { await connectionStore.saveEndpoint() }
                            }
                            .buttonStyle(.bordered)

                            Button("Generate Pairing Code") {
                                Task { await connectionStore.requestPairingCode() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pairing")
                            .font(.headline)

                        if let issued = connectionStore.issuedPairingCode {
                            statusRow(
                                title: "Issued Code",
                                detail: "\(issued.pairingCode) · expires \(issued.expiresAt.formatted(date: .omitted, time: .shortened))"
                            )
                        }

                        TextField("Pairing Code", text: Bindable(connectionStore).pairingCode)
                            .textFieldStyle(.roundedBorder)
                            .pairingCodeFieldStyle()

                        Button("Connect") {
                            Task { await connectionStore.connect() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(connectionStore.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(.headline)
                        statusRow(title: "Execution Mode", detail: appState.backendExecutionMode.rawValue.capitalized)
                        statusRow(
                            title: "Atlas",
                            detail: connectionStore.supportsAtlas ? "Available" : "Unavailable until the connection is established."
                        )

                        if connectionStore.isConnected {
                            Button("Open Preferences") {
                                appState.showPreferences()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Sign Out") {
                                Task { await connectionStore.signOut() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("iOS Status")
        }
    }

    private func statusRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    @ViewBuilder
    func remoteBackendURLFieldStyle() -> some View {
        #if os(iOS)
        self
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func pairingCodeFieldStyle() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

private struct MobileMoreView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Editing") {
                if appState.canEditNotes {
                    NavigationLink("Note Types") {
                        NotetypeListView()
                    }
                    NavigationLink("Image Occlusion") {
                        ImageOcclusionView()
                    }
                } else {
                    Text("Remote iOS backend currently ships study and browse only.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Import / Export") {
                if appState.canEditNotes {
                    NavigationLink("Import Package") {
                        ImportView()
                    }
                    NavigationLink("Import CSV") {
                        CsvImportView()
                    }
                    NavigationLink("Export Package") {
                        ExportView()
                    }
                } else {
                    Text("Import and export stay disabled while the remote transport is being proven.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Settings") {
                Button("Preferences") {
                    appState.isShowingPreferencesSheet = true
                }
                if appState.connectionStore?.isConnected == true {
                    Button("Sign Out") {
                        Task { await appState.connectionStore?.signOut() }
                    }
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
