import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isCollectionOpen: Bool = false
    var collectionPath: String = ""
    var error: AnkiError? = nil

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func openCollection(path: String) async {
        do {
            let mediaFolder = (path as NSString).deletingLastPathComponent + "/collection.media"
            let mediaDb = (path as NSString).deletingLastPathComponent + "/collection.media.db2"
            try await service.openCollection(path: path, mediaFolder: mediaFolder, mediaDb: mediaDb)
            collectionPath = path
            isCollectionOpen = true
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func closeCollection() async {
        do {
            try await service.closeCollection(downgrade: false)
            isCollectionOpen = false
        } catch let e as AnkiError {
            error = e
        } catch {}
    }
}
