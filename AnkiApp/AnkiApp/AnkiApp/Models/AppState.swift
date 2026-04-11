import AppleBridgeCore
import AppleSharedUI

// swiftlint:disable file_length
import Foundation
import Observation
#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

enum AppSheet: String, Identifiable {
    case addNote
    case reviewer

    var id: String {
        rawValue
    }
}

enum MobileTab: String, CaseIterable, Identifiable {
    case decks = "Decks"
    case browse = "Browse"
    case stats = "Stats"
    case sync = "Sync"
    case more = "More"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
            case .decks: "rectangle.stack"
            case .browse: "magnifyingglass"
            case .stats: "chart.bar"
            case .sync: "arrow.triangle.2.circlepath"
            case .more: "ellipsis.circle"
        }
    }
}

@Observable
@MainActor
final class SessionStore {
    var isCollectionOpen: Bool = false
    var collectionPath: String = ""
    var mediaFolderURL: URL?
    var error: AnkiError?
    var undoStatus: Anki_Collection_UndoStatus?
    var reviewPreferences = ReviewRuntimePreferences()

    var service: any AnkiServiceProtocol
    let ttsSettings = TTSSettings()
    var syncModel: SyncModel
    var atlasService: (any AtlasServiceProtocol)?
    var atlasServiceFactory: (() -> (any AtlasServiceProtocol)?)?

    var isAtlasAvailable: Bool {
        atlasService != nil
    }

    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?

    init(
        service: any AnkiServiceProtocol,
        atlasService: (any AtlasServiceProtocol)? = nil,
        atlasServiceFactory: (() -> (any AtlasServiceProtocol)?)? = nil
    ) {
        self.service = service
        syncModel = SyncModel(service: service)
        self.atlasService = atlasService
        self.atlasServiceFactory = atlasServiceFactory
    }

    func openCollection(path: String) async {
        let mediaFolder = (path as NSString).deletingLastPathComponent + "/collection.media"
        let mediaDb = (path as NSString).deletingLastPathComponent + "/collection.media.db2"
        do {
            try await service.openCollection(path: path, mediaFolder: mediaFolder, mediaDb: mediaDb)
            collectionPath = path
            mediaFolderURL = URL(fileURLWithPath: mediaFolder, isDirectory: true)
            isCollectionOpen = true
            error = nil
            await refreshUndoStatus()
            await refreshReviewPreferences()
            await reinitializeAtlas()
            refreshSyncSchedule()
            await performSyncOnOpenIfNeeded()
        } catch let error as AnkiError {
            self.error = error
            isCollectionOpen = false
        } catch {
            self.error = .message("Failed to open collection: \(error.localizedDescription)")
            isCollectionOpen = false
        }
    }

    func refreshUndoStatus() async {
        do {
            undoStatus = try await service.getUndoStatus()
        } catch {
            undoStatus = nil
        }
    }

    func reinitializeAtlas() async {
        atlasService = atlasServiceFactory?()
    }

    func updateServices(
        service: any AnkiServiceProtocol,
        atlasService: (any AtlasServiceProtocol)?,
        atlasServiceFactory: (() -> (any AtlasServiceProtocol)?)?
    ) {
        self.service = service
        syncModel = SyncModel(service: service)
        self.atlasService = atlasService
        self.atlasServiceFactory = atlasServiceFactory
    }

    func closeCollection() async {
        do {
            try await service.closeCollection(downgrade: false)
            isCollectionOpen = false
            collectionPath = ""
            mediaFolderURL = nil
            undoStatus = nil
            atlasService = nil
            reviewPreferences = ReviewRuntimePreferences()
            autoSyncTask?.cancel()
            autoSyncTask = nil
        } catch let error as AnkiError {
            self.error = error
        } catch {
            self.error = .message("Failed to close collection: \(error.localizedDescription)")
        }
    }

    func refreshReviewPreferences() async {
        do {
            let preferences = try await service.getPreferences()
            reviewPreferences = ReviewRuntimePreferences(reviewing: preferences.reviewing)
        } catch {
            reviewPreferences = ReviewRuntimePreferences()
        }
    }

    func refreshSyncSchedule() {
        autoSyncTask?.cancel()
        autoSyncTask = nil

        guard isCollectionOpen else { return }
        let intervalMinutes = SyncSettings.autoSyncIntervalMinutes
        guard intervalMinutes > 0 else { return }

        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(intervalMinutes * 60)))
                guard let self else { return }
                guard !Task.isCancelled else { return }
                await performAutomaticSyncIfNeeded()
            }
        }
    }

    private func performSyncOnOpenIfNeeded() async {
        guard SyncSettings.syncOnOpen else { return }
        await performAutomaticSyncIfNeeded()
    }

    private func performAutomaticSyncIfNeeded() async {
        guard isCollectionOpen, syncModel.isAuthenticated, !syncModel.isSyncing else {
            return
        }
        await syncModel.sync()
    }

    static func makeAtlasService() -> (any AtlasServiceProtocol)? {
        do {
            return try AtlasService(config: AtlasConfig.fromStoredSettings())
        } catch {
            return nil
        }
    }
}

@Observable
@MainActor
final class NavigationStore {
    var selectedSidebarItem: SidebarItem = .decks
    var selectedMobileTab: MobileTab = .decks
    var presentedSheet: AppSheet?
    var isShowingPreferencesSheet = false
    var selectedPreferencesTab: PreferencesTab = .general
}

@Observable
@MainActor
// swiftlint:disable type_body_length
final class AppState {
    let session: SessionStore
    let navigation = NavigationStore()
    let connectionStore: BackendConnectionStore?
    private let remoteSessionProvider: RemoteSessionProvider?
    private let preferredLanguages: [String]
    @ObservationIgnored private var appliedExecutionMode: BackendExecutionMode
    @ObservationIgnored private var pendingExecutionMode: BackendExecutionMode?
    @ObservationIgnored private var isApplyingExecutionModeChange = false

    init(
        service: any AnkiServiceProtocol,
        atlasService: (any AtlasServiceProtocol)? = nil,
        atlasServiceFactory: (() -> (any AtlasServiceProtocol)?)? = nil,
        connectionStore: BackendConnectionStore? = nil,
        remoteSessionProvider: RemoteSessionProvider? = nil,
        preferredLanguages: [String]
    ) {
        session = SessionStore(
            service: service,
            atlasService: atlasService,
            atlasServiceFactory: atlasServiceFactory
        )
        self.connectionStore = connectionStore
        self.remoteSessionProvider = remoteSessionProvider
        self.preferredLanguages = preferredLanguages
        appliedExecutionMode = Self.serviceExecutionMode(for: service)
    }

    convenience init() {
        #if os(iOS)
            let preferredLanguages = Self.preferredLanguages()
            let sessionProvider = RemoteSessionProvider(preferredLanguages: preferredLanguages)
            let connectionStore = BackendConnectionStore(
                sessionProvider: sessionProvider,
                localRuntimeProbe: { await Self.probeLocalRuntime(langs: preferredLanguages) }
            )
            self.init(
                service: UnavailableAnkiService(),
                atlasService: nil,
                atlasServiceFactory: nil,
                connectionStore: connectionStore,
                remoteSessionProvider: sessionProvider,
                preferredLanguages: preferredLanguages
            )
            connectionStore.onAvailabilityChange = { [weak self] in
                await self?.handleExecutionModeChangeIfNeeded()
            }
        #else
            let service = Self.makeService()
            self.init(
                service: service,
                atlasService: SessionStore.makeAtlasService(),
                atlasServiceFactory: { SessionStore.makeAtlasService() },
                preferredLanguages: Self.preferredLanguages()
            )
        #endif
    }

    static let unavailableBackendMessage =
        "This platform build does not have a connected Anki backend yet."

    var isCollectionOpen: Bool {
        session.isCollectionOpen
    }

    var collectionPath: String {
        session.collectionPath
    }

    var mediaFolderURL: URL? {
        session.mediaFolderURL
    }

    var error: AnkiError? {
        get { session.error }
        set { session.error = newValue }
    }

    var undoStatus: Anki_Collection_UndoStatus? {
        session.undoStatus
    }

    var reviewPreferences: ReviewRuntimePreferences {
        get { session.reviewPreferences }
        set { session.reviewPreferences = newValue }
    }

    var service: any AnkiServiceProtocol {
        session.service
    }

    var hasBackendService: Bool {
        #if os(iOS)
            connectionStore?.canServeBackend ?? false
        #else
            !(session.service is UnavailableAnkiService)
        #endif
    }

    var requiresBackendIntegration: Bool {
        !hasBackendService
    }

    var backendStatusTitle: String {
        #if os(iOS)
            if hasBackendService {
                switch backendExecutionMode {
                    case .local:
                        return "Local Backend Ready"
                    case .remote:
                        return "Remote Backend Connected"
                    case .unavailable:
                        return "Backend Ready"
                }
            }
            switch connectionStore?.selectedExecutionMode ?? .remote {
                case .local:
                return "Local Backend Unavailable"
                case .remote:
                switch connectionStore?.connectionState ?? .disconnected {
                    case .connecting:
                        return "Connecting to Backend"
                    case .error:
                        return "Connection Failed"
                    case .disconnected:
                        return "Remote Backend Required"
                    case .connected:
                        return "Remote Backend Unavailable"
                }
                case .unavailable:
                return "Backend Selection Required"
            }
        #else
            return hasBackendService ? "Backend Ready" : "Backend Integration Required"
        #endif
    }

    var backendStatusMessage: String {
        if hasBackendService {
            #if os(iOS)
                switch backendExecutionMode {
                    case .local:
                    return atlasSetupStatus.summary
                    case .remote:
                    return "This iOS build is connected to a remote Anki backend. Open Preferences to select a collection path on the companion or cloud host."
                    case .unavailable:
                    return "Backend ready."
                }
            #else
                return "This app target has access to the Anki backend."
            #endif
        }

        #if os(iOS)
            if connectionStore?.selectedExecutionMode == .local {
                return atlasSetupStatus.summary
            }
            return connectionStore?.lastErrorMessage
                ?? connectionStore?.runtimeStatusMessage
                ?? "Enter a backend URL, pair with the companion or cloud deployment, and then switch back to Remote mode."
        #else
            return Self.unavailableBackendMessage
        #endif
    }

    var ttsSettings: TTSSettings {
        session.ttsSettings
    }

    var syncModel: SyncModel {
        session.syncModel
    }

    var atlasService: (any AtlasServiceProtocol)? {
        get { session.atlasService }
        set { session.atlasService = newValue }
    }

    var isAtlasAvailable: Bool {
        #if os(iOS)
            if backendExecutionMode == .local {
                session.isAtlasAvailable
            } else {
                connectionStore?.supportsAtlas ?? false
            }
        #else
            session.isAtlasAvailable
        #endif
    }

    var backendExecutionMode: BackendExecutionMode {
        #if os(iOS)
            connectionStore?.executionMode ?? .unavailable
        #else
            .local
        #endif
    }

    var selectedPreferencesTab: PreferencesTab {
        get { navigation.selectedPreferencesTab }
        set { navigation.selectedPreferencesTab = newValue }
    }

    var atlasSetupStatus: AtlasSetupStatus {
        #if os(iOS)
            switch connectionStore?.selectedExecutionMode ?? .remote {
                case .local:
                return localAtlasSetupStatus()
                case .remote:
                return remoteAtlasSetupStatus()
                case .unavailable:
                return remoteAtlasSetupStatus()
            }
        #else
            return localAtlasSetupStatus()
        #endif
    }

    var canEditNotes: Bool {
        #if os(iOS)
            hasBackendService
        #else
            true
        #endif
    }

    var selectedSidebarItem: SidebarItem {
        get { navigation.selectedSidebarItem }
        set { navigation.selectedSidebarItem = newValue }
    }

    var selectedMobileTab: MobileTab {
        get { navigation.selectedMobileTab }
        set { navigation.selectedMobileTab = newValue }
    }

    var isShowingAddNote: Bool {
        get { navigation.presentedSheet == .addNote }
        set {
            if newValue {
                navigation.presentedSheet = .addNote
            } else if navigation.presentedSheet == .addNote {
                navigation.presentedSheet = nil
            }
        }
    }

    var isShowingReviewer: Bool {
        get { navigation.presentedSheet == .reviewer }
        set {
            if newValue {
                navigation.presentedSheet = .reviewer
            } else if navigation.presentedSheet == .reviewer {
                navigation.presentedSheet = nil
            }
        }
    }

    var isShowingPreferencesSheet: Bool {
        get { navigation.isShowingPreferencesSheet }
        set { navigation.isShowingPreferencesSheet = newValue }
    }

    func openCollection(path: String) async {
        await session.openCollection(path: path)
        if session.isCollectionOpen {
            navigation.isShowingPreferencesSheet = false
        }
    }

    func refreshUndoStatus() async {
        await session.refreshUndoStatus()
    }

    func reinitializeAtlas() async {
        await session.reinitializeAtlas()
    }

    func retryAtlasSetup() async {
        await session.reinitializeAtlas()
        #if os(iOS)
            await refreshLocalRuntimeStatus()
        #endif
    }

    func closeCollection() async {
        await session.closeCollection()
        navigation.presentedSheet = nil
        #if os(iOS)
            await resolvePendingExecutionModeIfNeeded()
        #endif
    }

    func restoreBackendState() async {
        #if os(iOS)
            await connectionStore?.restore()
            await handleExecutionModeChangeIfNeeded(force: true)
        #endif
    }

    func selectExecutionMode(_ mode: BackendExecutionMode) async {
        #if os(iOS)
            pendingExecutionMode = nil
            if isCollectionOpen {
                await closeCollection()
            }
            await connectionStore?.selectExecutionMode(mode)
            await handleExecutionModeChangeIfNeeded(force: true)
        #endif
    }

    func signOutRemoteBackend() async {
        #if os(iOS)
            pendingExecutionMode = nil
            if isCollectionOpen, connectionStore?.selectedExecutionMode == .remote {
                await closeCollection()
            }
            await connectionStore?.signOut()
            await handleExecutionModeChangeIfNeeded(force: true)
        #endif
    }

    func presentAddNote() {
        guard isCollectionOpen else {
            error = .message("Open a collection before adding notes.")
            return
        }
        navigation.presentedSheet = .addNote
    }

    func startReview(deckId: Int64? = nil) async {
        guard isCollectionOpen else {
            error = .message("Open a collection before starting review.")
            return
        }
        do {
            await refreshReviewPreferences()
            if let deckId {
                try await service.setCurrentDeck(deckId: deckId)
            }
            navigation.presentedSheet = .reviewer
        } catch let error as AnkiError {
            self.error = error
        } catch {
            self.error = .message("Failed to start review: \(error.localizedDescription)")
        }
    }

    func dismissPresentedSheet() {
        navigation.presentedSheet = nil
        #if os(iOS)
            Task { await resolvePendingExecutionModeIfNeeded() }
        #endif
    }

    func refreshReviewPreferences() async {
        await session.refreshReviewPreferences()
    }

    func refreshSyncSchedule() {
        session.refreshSyncSchedule()
    }

    func resolvePendingExecutionModeIfNeeded() async {
        #if os(iOS)
            guard let pendingExecutionMode else { return }
            await handleExecutionModeChangeIfNeeded(force: true, preferredTargetMode: pendingExecutionMode)
        #endif
    }

    func syncNow() async {
        await syncModel.sync()
        await resolvePendingExecutionModeIfNeeded()
    }

    func performFullSync(upload: Bool, serverMediaUsn: Int32) async {
        await syncModel.performFullSync(upload: upload, serverMediaUsn: serverMediaUsn)
        await resolvePendingExecutionModeIfNeeded()
    }

    #if os(iOS)
        func saveBackendEndpoint() async {
            await connectionStore?.saveEndpoint()
            await handleExecutionModeChangeIfNeeded(force: true)
        }

        func verifyBackendConnection() async {
            await connectionStore?.verifyConnection()
            await handleExecutionModeChangeIfNeeded(force: true)
        }

        func requestBackendPairingCode() async {
            await connectionStore?.requestPairingCode()
            await handleExecutionModeChangeIfNeeded(force: true)
        }

        func discoverCompanionBackend() async {
            await connectionStore?.discoverCompanion()
            await handleExecutionModeChangeIfNeeded(force: true)
        }

        func refreshLocalRuntimeStatus() async {
            await connectionStore?.refreshLocalRuntimeStatus()
            await handleExecutionModeChangeIfNeeded(force: true)
        }

        func connectRemoteBackend() async {
            await connectionStore?.connect()
            await handleExecutionModeChangeIfNeeded(force: true)
        }

        func refreshBackendStatus() async {
            await connectionStore?.refreshStatus()
            await handleExecutionModeChangeIfNeeded(force: true)
        }
    #endif

    func showPreferences(tab: PreferencesTab = .general) {
        navigation.selectedPreferencesTab = tab
        #if os(macOS)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        #else
            navigation.isShowingPreferencesSheet = true
        #endif
    }

    func showAtlasSettings() {
        showPreferences(tab: .atlas)
    }

    func openExternalURL(_ url: URL) {
        #if os(macOS)
            NSWorkspace.shared.open(url)
        #elseif os(iOS)
            UIApplication.shared.open(url)
        #endif
    }

    private static func makeService() -> any AnkiServiceProtocol {
        do {
            return try AnkiService(langs: preferredLanguages())
        } catch {
            return UnavailableAnkiService()
        }
    }

    private static func serviceExecutionMode(for service: any AnkiServiceProtocol) -> BackendExecutionMode {
        if service is RemoteAnkiService {
            return .remote
        }
        if service is UnavailableAnkiService {
            return .unavailable
        }
        return .local
    }

    private func localAtlasSetupStatus() -> AtlasSetupStatus {
        let config = AtlasConfig.fromStoredSettings()
        let checklist = config.localSetupChecklist
        let localRuntimeStatus = connectionStore?.localRuntimeStatus
        let atlasAvailable = session.isAtlasAvailable || localRuntimeStatus?.atlasAvailability == .available
        let atlasMessage = localRuntimeStatus?.atlasMessage
        let detailMessage = localRuntimeStatus?.detailMessage

        if atlasAvailable {
            return AtlasSetupStatus(
                kind: .ready,
                title: "Local Atlas Ready",
                summary: atlasMessage
                    ?? "Atlas is running on this device. Search, analytics, and graph features are available.",
                guidance: "If Atlas stops responding, reopen the Atlas tab in Preferences and restart the local runtime.",
                checklist: checklist,
                showsRetryAction: true
            )
        }

        if !config.localSetupIsComplete || localRuntimeStatus?.atlasAvailability == .configurationMissing {
            return AtlasSetupStatus(
                kind: .needsConfiguration,
                title: "Finish Local Atlas Setup",
                summary: atlasMessage
                    ??
                    "Local Atlas needs PostgreSQL and embedding settings before smart search, analytics, and graph tools can start.",
                guidance: "Open the Atlas tab in Preferences, fill the missing items below, then restart Atlas.",
                checklist: checklist,
                showsRetryAction: false
            )
        }

        return AtlasSetupStatus(
            kind: .unavailable,
            title: "Local Atlas Could Not Start",
            summary: atlasMessage
                ?? "Atlas settings are present, but the local runtime could not be created.",
            guidance: detailMessage
                ??
                "Check the PostgreSQL URL, provider credentials, and network access, then retry the local Atlas startup.",
            checklist: checklist,
            showsRetryAction: true
        )
    }

    private func remoteAtlasSetupStatus() -> AtlasSetupStatus {
        if connectionStore?.supportsAtlas == true {
            return AtlasSetupStatus(
                kind: .ready,
                title: "Remote Atlas Ready",
                summary: "The connected companion or cloud backend exposes Atlas features.",
                guidance: "Open any Atlas screen to use smart search, analytics, or the knowledge graph.",
                checklist: [],
                showsRetryAction: false
            )
        }

        if connectionStore?.isConnected == true {
            return AtlasSetupStatus(
                kind: .unavailable,
                title: "Remote Atlas Not Enabled",
                summary: "This backend is connected, but it is not currently advertising Atlas support.",
                guidance: "Enable Atlas on the companion or cloud host, then refresh the backend status.",
                checklist: [],
                showsRetryAction: false
            )
        }

        return AtlasSetupStatus(
            kind: .unavailable,
            title: "Remote Atlas Needs a Backend",
            summary: "Connect to a companion or cloud backend that exposes Atlas features.",
            guidance: "Finish pairing with a backend, then refresh the connection status.",
            checklist: [],
            showsRetryAction: false
        )
    }

    #if os(iOS)
        private func refreshServiceBindings(closeCollectionIfNeeded: Bool) async {
            if closeCollectionIfNeeded, isCollectionOpen {
                await closeCollection()
            }

            let bindings = resolveIOSServices()
            session.updateServices(
                service: bindings.service,
                atlasService: bindings.atlasService,
                atlasServiceFactory: bindings.atlasServiceFactory
            )
            appliedExecutionMode = Self.serviceExecutionMode(for: bindings.service)
            await refreshReviewPreferences()
        }

        private struct IOSServiceBindings {
            let service: any AnkiServiceProtocol
            let atlasService: (any AtlasServiceProtocol)?
            let atlasServiceFactory: (() -> (any AtlasServiceProtocol)?)?
        }

        // swiftlint:disable function_body_length
        private func resolveIOSServices() -> IOSServiceBindings {
            guard let connectionStore else {
                return IOSServiceBindings(
                    service: UnavailableAnkiService(),
                    atlasService: nil,
                    atlasServiceFactory: nil
                )
            }

            switch connectionStore.executionMode {
                case .remote:
                    guard connectionStore.remoteBackendReady, let remoteSessionProvider else {
                        return IOSServiceBindings(
                            service: UnavailableAnkiService(),
                            atlasService: nil,
                            atlasServiceFactory: nil
                        )
                    }
                    let atlasFactory = {
                        RemoteAtlasService(sessionProvider: remoteSessionProvider) as any AtlasServiceProtocol
                    }
                    return IOSServiceBindings(
                        service: RemoteAnkiService(sessionProvider: remoteSessionProvider),
                        atlasService: atlasFactory(),
                        atlasServiceFactory: atlasFactory
                    )
                case .local:
                    guard connectionStore.localBackendReady else {
                        return IOSServiceBindings(
                            service: UnavailableAnkiService(),
                            atlasService: nil,
                            atlasServiceFactory: nil
                        )
                    }
                    let localService: any AnkiServiceProtocol = if let service =
                        try? AnkiService(langs: preferredLanguages) {
                        service
                    } else {
                        UnavailableAnkiService()
                    }
                    let atlasFactory = { SessionStore.makeAtlasService() }
                    return IOSServiceBindings(
                        service: localService,
                        atlasService: atlasFactory(),
                        atlasServiceFactory: atlasFactory
                    )
                case .unavailable:
                    return IOSServiceBindings(
                        service: UnavailableAnkiService(),
                        atlasService: nil,
                        atlasServiceFactory: nil
                    )
            }
        }

        // swiftlint:enable function_body_length

        private static func probeLocalRuntime(langs: [String]) async -> LocalRuntimeStatus {
            do {
                _ = try AnkiService(langs: langs)
            } catch {
                return .unavailable(message: "Local iOS backend could not start: \(error.localizedDescription)")
            }

            let atlasConfig = AtlasConfig.fromStoredSettings()
            let hasAtlasConfig =
                [atlasConfig.postgresUrl, atlasConfig.embeddingProvider, atlasConfig.embeddingModel]
                    .allSatisfy { value in
                        guard let value else { return false }
                        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }

            if hasAtlasConfig {
                if let atlasService = SessionStore.makeAtlasService() {
                    _ = atlasService
                    return .ready(atlasAvailability: .available)
                }
                return .ready(
                    atlasAvailability: .unavailable,
                    atlasMessage: "Atlas settings are present, but the local Atlas runtime could not be created."
                )
            }

            return .ready(
                atlasAvailability: .configurationMissing,
                atlasMessage: "Atlas is available in local mode after you provide PostgreSQL and embedding settings."
            )
        }

        // swiftlint:disable cyclomatic_complexity
        private func handleExecutionModeChangeIfNeeded(
            force: Bool = false,
            preferredTargetMode: BackendExecutionMode? = nil
        ) async {
            guard let connectionStore else { return }

            let targetMode = preferredTargetMode ?? connectionStore.executionMode
            guard force || targetMode != appliedExecutionMode else { return }
            guard !isApplyingExecutionModeChange else { return }

            if shouldDeferExecutionModeChange(to: targetMode) {
                pendingExecutionMode = targetMode
                connectionStore.runtimeStatusMessage = deferredExecutionModeMessage(for: targetMode)
                return
            }

            isApplyingExecutionModeChange = true
            defer { isApplyingExecutionModeChange = false }

            let wasCollectionOpen = isCollectionOpen
            let reopenPath = wasCollectionOpen ? collectionPathForExecutionMode(targetMode) : nil

            if wasCollectionOpen,
               targetMode != .unavailable,
               syncModel.isAuthenticated,
               !syncModel.isSyncing {
                await syncModel.sync()
                if case .fullSyncRequired = syncModel.state {
                    pendingExecutionMode = targetMode
                    connectionStore.runtimeStatusMessage =
                        "Automatic failover paused until the required AnkiWeb full sync is completed."
                    return
                }
                if case .error = syncModel.state {
                    pendingExecutionMode = targetMode
                    connectionStore.runtimeStatusMessage =
                        "Automatic failover paused until the current sync error is resolved."
                    return
                }
            }

            pendingExecutionMode = nil
            navigation.presentedSheet = nil

            if wasCollectionOpen {
                await session.closeCollection()
            }

            await refreshServiceBindings(closeCollectionIfNeeded: false)

            if let reopenPath, targetMode != .unavailable {
                await openCollection(path: reopenPath)
                if !session.isCollectionOpen {
                    connectionStore.runtimeStatusMessage = missingCollectionReopenMessage(for: targetMode)
                }
            } else if wasCollectionOpen, targetMode != .unavailable {
                connectionStore.runtimeStatusMessage = missingCollectionReopenMessage(for: targetMode)
            }
        }

        // swiftlint:enable cyclomatic_complexity

        private func shouldDeferExecutionModeChange(to targetMode: BackendExecutionMode) -> Bool {
            guard targetMode != appliedExecutionMode else { return false }
            guard isCollectionOpen else { return false }
            if syncModel.isSyncing {
                return true
            }
            return navigation.presentedSheet == .reviewer
        }

        private func deferredExecutionModeMessage(for targetMode: BackendExecutionMode) -> String {
            if syncModel.isSyncing {
                return "Automatic failover to \(targetMode == .local ? "Local" : "Remote") is waiting for the current sync to finish."
            }
            if navigation.presentedSheet == .reviewer {
                return "Automatic failover to \(targetMode == .local ? "Local" : "Remote") is waiting for the active review session to end."
            }
            return "Automatic failover is pending."
        }

        private func collectionPathForExecutionMode(_ mode: BackendExecutionMode) -> String? {
            switch mode {
                case .local:
                    return ProfileManager().activeProfile?.path
                case .remote:
                    let storedPath = UserDefaults.standard.string(forKey: "collectionPath")?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let storedPath, !storedPath.isEmpty {
                        return storedPath
                    }
                    return nil
                case .unavailable:
                    return nil
            }
        }

        private func missingCollectionReopenMessage(for mode: BackendExecutionMode) -> String {
            switch mode {
                case .local:
                    "Automatic failover switched to Local mode. Import or select a sandboxed local profile to reopen the collection."
                case .remote:
                    "Automatic failover switched to Remote mode. Select a remote collection path in Preferences to reopen the collection."
                case .unavailable:
                    "No backend is currently available."
            }
        }
    #endif

    private static func preferredLanguages() -> [String] {
        let storedLanguage = UserDefaults.standard.string(forKey: "language")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var languages: [String] = []
        if let storedLanguage, !storedLanguage.isEmpty {
            languages.append(storedLanguage)
        }

        for locale in Locale.preferredLanguages where !languages.contains(locale) {
            languages.append(locale)
        }

        return languages.isEmpty ? ["en"] : languages
    }
}

// swiftlint:enable type_body_length

#if !os(iOS)
    extension AppState {
        func saveBackendEndpoint() async {}
        func verifyBackendConnection() async {}
        func requestBackendPairingCode() async {}
        func discoverCompanionBackend() async {}
        func refreshLocalRuntimeStatus() async {}
        func connectRemoteBackend() async {}
        func refreshBackendStatus() async {}
    }
#endif
// swiftlint:enable file_length
