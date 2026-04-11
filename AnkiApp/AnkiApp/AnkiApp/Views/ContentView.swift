// swiftlint:disable file_length type_body_length function_body_length
import SwiftUI
import AppleBridgeCore
import AppleSharedUI
#if os(iOS)
import CoreImage.CIFilterBuiltins
import UIKit
#endif

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
                IOSBackendOnboardingView()
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

private struct IOSBackendOnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        guard let connectionStore = appState.connectionStore else {
            return AnyView(
                ContentUnavailableView(
                    "Backend Unavailable",
                    systemImage: "wifi.slash",
                    description: Text("The app could not create a backend connection store.")
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
                    statusHeader
                    executionSection(connectionStore: connectionStore)
                    if connectionStore.selectedExecutionMode == .remote {
                        connectionSection(connectionStore: connectionStore)
                        pairingSection(connectionStore: connectionStore)
                    } else {
                        localSection(connectionStore: connectionStore)
                    }
                    statusSection(connectionStore: connectionStore)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("iOS Status")
        }
    }

    private var statusHeader: some View {
        ContentUnavailableView(
            appState.backendStatusTitle,
            systemImage: "iphone.and.arrow.forward",
            description: Text(appState.backendStatusMessage)
        )
    }

    private func executionSection(connectionStore: BackendConnectionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution")
                .font(.headline)

            Picker(
                "Execution Mode",
                selection: Binding(
                    get: { connectionStore.selectedExecutionMode },
                    set: { newMode in
                        Task { await appState.selectExecutionMode(newMode) }
                    }
                )
            ) {
                Text("Remote").tag(BackendExecutionMode.remote)
                Text("Local").tag(BackendExecutionMode.local)
            }
            .pickerStyle(.segmented)

            Text(
                connectionStore.runtimeStatusMessage
                    ?? "Choose whether iOS should run against the remote backend or the local on-device runtime."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func connectionSection(connectionStore: BackendConnectionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote Connection")
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

            if connectionStore.deploymentKind == .cloud {
                SecureField("Cloud Pairing Secret", text: Bindable(connectionStore).cloudPairingKey)
                    .textFieldStyle(.roundedBorder)
                Text("Cloud deployments require the pairing secret to issue a new pairing code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Save Endpoint") {
                    Task { await appState.saveBackendEndpoint() }
                }
                .buttonStyle(.bordered)

                Button("Test Connection") {
                    Task { await appState.verifyBackendConnection() }
                }
                .buttonStyle(.bordered)

                Button("Generate Pairing Code") {
                    Task { await appState.requestBackendPairingCode() }
                }
                .buttonStyle(.bordered)
                .disabled(
                    connectionStore.deploymentKind == .cloud
                        && connectionStore.cloudPairingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if connectionStore.deploymentKind == .companion {
                discoverySection(connectionStore: connectionStore)
            }
        }
    }

    @ViewBuilder
    private func discoverySection(connectionStore: BackendConnectionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Companion Discovery")
                .font(.subheadline.weight(.semibold))

            Text("Scan common local companion addresses, then pick the one running on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await appState.discoverCompanionBackend() }
            } label: {
                if connectionStore.isDiscoveringCompanion {
                    Label("Scanning for Companion", systemImage: "dot.radiowaves.left.and.right")
                } else {
                    Label("Scan for Companion", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(connectionStore.isDiscoveringCompanion)

            if connectionStore.isDiscoveringCompanion {
                ProgressView("Probing local endpoints…")
                    .font(.caption)
            }

            if !connectionStore.discoveredCompanionCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(connectionStore.discoveredCompanionCandidates) { candidate in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.label)
                                        .font(.subheadline.weight(.semibold))
                                    Text(candidate.endpoint.baseURL.absoluteString)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(
                                    candidate.endpoint.baseURL.absoluteString == connectionStore.endpointURLString
                                        ? "Selected"
                                        : "Use"
                                ) {
                                    Task { await connectionStore.selectDiscoveredCompanion(candidate) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(candidate.endpoint.baseURL.absoluteString == connectionStore.endpointURLString)
                            }
                            Text(candidate.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func localSection(connectionStore: BackendConnectionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Runtime")
                .font(.headline)

            statusRow(
                title: "Bridge",
                detail: connectionStore.localRuntimeStatus.bridgeAvailable ? "Available" : "Unavailable"
            )
            statusRow(
                title: "Anki Runtime",
                detail: connectionStore.localRuntimeStatus.ankiAvailable ? "Ready" : "Not Ready"
            )
            statusRow(
                title: "Atlas",
                detail: atlasDetail(from: connectionStore.localRuntimeStatus)
            )

            AtlasSetupStatusPanel(status: appState.atlasSetupStatus)

            HStack {
                Button("Open Atlas Settings") {
                    appState.showAtlasSettings()
                }
                .buttonStyle(.borderedProminent)

                if appState.atlasSetupStatus.showsRetryAction {
                    Button("Retry Atlas Startup") {
                        Task { await appState.retryAtlasSetup() }
                    }
                    .buttonStyle(.bordered)
                }

                Button("Probe Local Runtime") {
                    Task {
                        await appState.refreshLocalRuntimeStatus()
                        await appState.selectExecutionMode(.local)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func pairingSection(connectionStore: BackendConnectionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pairing")
                .font(.headline)

            Text("Generate a code on iPhone, then open the link or enter the code on the Mac that is running the companion.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let issued = connectionStore.issuedPairingCode {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow(
                        title: "Issued Code",
                        detail: "Expires \(issued.expiresAt.formatted(date: .omitted, time: .shortened))"
                    )

                    Text(issued.pairingCode)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                    #if os(iOS)
                    if let pairingURL = issued.pairingURL {
                        PairingQRCodeView(url: pairingURL)
                    }
                    #endif

                    HStack {
                        #if os(iOS)
                        Button("Copy Code") {
                            UIPasteboard.general.string = issued.pairingCode
                            connectionStore.runtimeStatusMessage = "Copied pairing code."
                        }
                        .buttonStyle(.bordered)
                        #endif

                        if let pairingURL = issued.pairingURL {
                            ShareLink(item: pairingURL) {
                                Label("Share Link", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)

                            #if os(iOS)
                            Button("Copy Link") {
                                UIPasteboard.general.url = pairingURL
                                connectionStore.runtimeStatusMessage = "Copied pairing link."
                            }
                            .buttonStyle(.bordered)
                            #endif

                            Link("Open Pairing Link", destination: pairingURL)
                                .font(.callout.weight(.semibold))
                        }
                    }
                }

                Text("Tip: if the link opens on the wrong device, copy the code instead and paste it into the companion pairing prompt on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Pairing Code", text: Bindable(connectionStore).pairingCode)
                .textFieldStyle(.roundedBorder)
                .pairingCodeFieldStyle()

            Button("Connect") {
                Task {
                    await appState.connectRemoteBackend()
                    await appState.selectExecutionMode(.remote)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(connectionStore.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func statusSection(connectionStore: BackendConnectionStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
            statusRow(title: "Selected Mode", detail: connectionStore.selectedExecutionMode.displayName)
            statusRow(title: "Active Mode", detail: appState.backendExecutionMode.displayName)
            if let endpoint = connectionStore.lastVerifiedEndpoint {
                statusRow(title: "Verified Endpoint", detail: endpoint.baseURL.absoluteString)
            }
            if connectionStore.selectedExecutionMode == .remote {
                statusRow(
                    title: "Atlas",
                    detail: connectionStore.supportsAtlas ? "Available" : "Unavailable until the connection is established."
                )
            }

            Button("Refresh Status") {
                Task {
                    await appState.refreshBackendStatus()
                    await appState.selectExecutionMode(connectionStore.selectedExecutionMode)
                }
            }
            .buttonStyle(.bordered)

            if appState.hasBackendService {
                Button(connectionStore.selectedExecutionMode == .local ? "Open Atlas Settings" : "Open Preferences") {
                    if connectionStore.selectedExecutionMode == .local {
                        appState.showAtlasSettings()
                    } else {
                        appState.showPreferences()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if connectionStore.isConnected {
                Button("Sign Out") {
                    Task { await appState.signOutRemoteBackend() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func atlasDetail(from localRuntimeStatus: LocalRuntimeStatus) -> String {
        switch localRuntimeStatus.atlasAvailability {
            case .available:
                return localRuntimeStatus.atlasMessage ?? "Available"
            case .configurationMissing:
                return localRuntimeStatus.atlasMessage ?? "Configuration Missing"
            case .unavailable:
                return localRuntimeStatus.atlasMessage ?? "Unavailable"
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

#if os(iOS)
private struct PairingQRCodeView: View {
    let url: URL

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image = qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var qrImage: UIImage? {
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
#endif

private extension BackendExecutionMode {
    var displayName: String {
        switch self {
            case .local:
                "Local"
            case .remote:
                "Remote"
            case .unavailable:
                "Unavailable"
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
                if appState.connectionStore?.isConnected == true {
                    Button("Sign Out") {
                        Task { await appState.signOutRemoteBackend() }
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
// swiftlint:enable type_body_length
// swiftlint:enable function_body_length
