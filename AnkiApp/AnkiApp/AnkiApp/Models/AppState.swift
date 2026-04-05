import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isCollectionOpen: Bool = false
    var collectionPath: String = ""
    var selectedSidebarItem: SidebarItem = .decks
    var error: AnkiError? = nil

    let service: AnkiService

    init() {
        do {
            self.service = try AnkiService(langs: Locale.preferredLanguages)
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
            isCollectionOpen = true
            self.error = nil
        } catch let e as AnkiError {
            self.error = e
        } catch {}
    }

    func closeCollection() async {
        do {
            try await service.closeCollection(downgrade: false)
            isCollectionOpen = false
        } catch let e as AnkiError {
            self.error = e
        } catch {}
    }
}
