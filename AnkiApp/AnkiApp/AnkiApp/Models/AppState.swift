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

    let service: any AnkiServiceProtocol
    let ttsSettings = TTSSettings()
    var atlasService: (any AtlasServiceProtocol)?
    var isAtlasAvailable: Bool {
        atlasService != nil
    }

    init() {
        do {
            service = try AnkiService(langs: Locale.preferredLanguages)
        } catch {
            service = UnavailableAnkiService()
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
            await reinitializeAtlas()
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
}
