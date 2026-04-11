// swiftlint:disable file_length
import Foundation
import Observation
import AppleBridgeCore
import AppleSharedUI
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

    let service: any AnkiServiceProtocol
    let ttsSettings = TTSSettings()
    let syncModel: SyncModel
    var atlasService: (any AtlasServiceProtocol)?

    var isAtlasAvailable: Bool {
        atlasService != nil
    }

    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?

    init(service: any AnkiServiceProtocol, atlasService: (any AtlasServiceProtocol)? = nil) {
        self.service = service
        syncModel = SyncModel(service: service)
        self.atlasService = atlasService
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
        atlasService = Self.makeAtlasService()
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
        #if os(macOS)
        do {
            return try AtlasService(config: AtlasConfig.fromStoredSettings())
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

@Observable
@MainActor
final class NavigationStore {
    var selectedSidebarItem: SidebarItem = .decks
    var selectedMobileTab: MobileTab = .decks
    var presentedSheet: AppSheet?
    var isShowingPreferencesSheet = false
}

@Observable
@MainActor
final class AppState {
    let session: SessionStore
    let navigation = NavigationStore()
    let connectionStore: BackendConnectionStore?

    init(
        service: any AnkiServiceProtocol,
        atlasService: (any AtlasServiceProtocol)? = nil,
        connectionStore: BackendConnectionStore? = nil
    ) {
        session = SessionStore(service: service, atlasService: atlasService)
        self.connectionStore = connectionStore
    }

    convenience init() {
        #if os(iOS)
        let sessionProvider = RemoteSessionProvider(preferredLanguages: Self.preferredLanguages())
        let connectionStore = BackendConnectionStore(sessionProvider: sessionProvider)
        self.init(
            service: RemoteAnkiService(sessionProvider: sessionProvider),
            atlasService: RemoteAtlasService(sessionProvider: sessionProvider),
            connectionStore: connectionStore
        )
        #else
        let service = Self.makeService()
        self.init(service: service, atlasService: SessionStore.makeAtlasService())
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
            return "Remote Backend Connected"
        }
        switch connectionStore?.connectionState ?? .disconnected {
            case .connecting:
                return "Connecting to Backend"
            case let .error(message):
                return message.isEmpty ? "Connection Failed" : "Connection Failed"
            case .disconnected:
                return "Remote Backend Required"
            case .connected:
                return "Backend Policy Requires Another Mode"
        }
        #else
        return hasBackendService ? "Backend Ready" : "Backend Integration Required"
        #endif
    }

    var backendStatusMessage: String {
        if hasBackendService {
            #if os(iOS)
            return "This iOS build is connected to a remote Anki backend. Open Preferences to select a collection path on the companion or cloud host."
            #else
            return "This app target has access to the Anki backend."
            #endif
        }

        #if os(iOS)
        return connectionStore?.lastErrorMessage
            ?? connectionStore?.runtimeStatusMessage
            ?? "Enter a backend URL, pair with the companion or cloud deployment, and then open a remote collection from Preferences."
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
        connectionStore?.supportsAtlas ?? false
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

    func closeCollection() async {
        await session.closeCollection()
        navigation.presentedSheet = nil
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
    }

    func refreshReviewPreferences() async {
        await session.refreshReviewPreferences()
    }

    func refreshSyncSchedule() {
        session.refreshSyncSchedule()
    }

    func showPreferences() {
        #if os(macOS)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        #else
        navigation.isShowingPreferencesSheet = true
        #endif
    }

    func openExternalURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private static func makeService() -> any AnkiServiceProtocol {
        #if os(macOS)
        do {
            return try AnkiService(langs: preferredLanguages())
        } catch {
            return UnavailableAnkiService()
        }
        #else
        return UnavailableAnkiService()
        #endif
    }

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
// swiftlint:enable file_length
