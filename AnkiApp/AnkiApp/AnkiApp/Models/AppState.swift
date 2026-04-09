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

    let service: AnkiService
    let ttsSettings = TTSSettings()
    var atlasService: (any AtlasServiceProtocol)?
    var isAtlasAvailable: Bool {
        atlasService != nil
    }

    init() {
        do {
            service = try AnkiService(langs: Locale.preferredLanguages)
        } catch {
            fatalError("Failed to initialize Anki backend: \(error)")
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
        } catch {}
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
        } catch let error as AnkiError {
            self.error = error
        } catch {}
    }
}
