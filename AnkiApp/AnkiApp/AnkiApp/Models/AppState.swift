import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isCollectionOpen: Bool = false
    var collectionPath: String = ""
    var mediaFolderURL: URL?
    var selectedSidebarItem: SidebarItem = .decks
    var error: AnkiError?
    var undoStatus: Anki_Collection_UndoStatus?
    var isShowingAddNote = false
    var isShowingReviewer = false
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
        self.syncModel = SyncModel(service: service)
        self.atlasService = atlasService
    }

    convenience init() {
        do {
            let service = try AnkiService(langs: Self.preferredLanguages())
            self.init(service: service)
        } catch {
            self.init(service: UnavailableAnkiService())
            self.error = .message("Failed to initialize the Anki backend: \(error)")
        }
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
        let config = AtlasConfig.fromStoredSettings()
        do {
            atlasService = try AtlasService(config: config)
        } catch {
            atlasService = nil
        }
    }

    func closeCollection() async {
        do {
            try await service.closeCollection(downgrade: false)
            isCollectionOpen = false
            collectionPath = ""
            mediaFolderURL = nil
            undoStatus = nil
            atlasService = nil
            isShowingReviewer = false
            reviewPreferences = ReviewRuntimePreferences()
            autoSyncTask?.cancel()
            autoSyncTask = nil
        } catch let error as AnkiError {
            self.error = error
        } catch {
            self.error = .message("Failed to close collection: \(error.localizedDescription)")
        }
    }

    func presentAddNote() {
        guard isCollectionOpen else {
            error = .message("Open a collection before adding notes.")
            return
        }
        isShowingAddNote = true
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
            isShowingReviewer = true
        } catch let error as AnkiError {
            self.error = error
        } catch {
            self.error = .message("Failed to start review: \(error.localizedDescription)")
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
                await self.performAutomaticSyncIfNeeded()
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
