import Foundation
import Observation

@Observable
@MainActor
final class DeckBrowserModel {
    var deckTree: Anki_Decks_DeckTreeNode? = nil
    var isLoading: Bool = false
    var error: AnkiError? = nil

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let now = Int64(Date().timeIntervalSince1970)
            deckTree = try await service.getDeckTree(now: now)
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }
}
