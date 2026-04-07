import Foundation
import Observation

@Observable
@MainActor
final class SyncModel {
    var isSyncing: Bool = false
    var lastSyncError: AnkiError?
    var tags: [String] = []

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadTags() async {
        do {
            let result = try await service.allTags()
            tags = result.vals
            lastSyncError = nil
        } catch let e as AnkiError {
            lastSyncError = e
        } catch {}
    }
}
