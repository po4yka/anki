import Foundation
import Observation

@Observable
@MainActor
final class DeckBrowserModel {
    var deckTree: Anki_Decks_DeckTreeNode?
    var isLoading: Bool = false
    var error: AnkiError?

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
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func createDeck(name: String) async {
        do {
            var deck = try await service.newDeck()
            deck.name = name
            _ = try await service.addDeck(deck: deck)
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func renameDeck(deckId: Int64, newName: String) async {
        do {
            _ = try await service.renameDeck(deckId: deckId, newName: newName)
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func deleteDeck(deckId: Int64) async {
        do {
            _ = try await service.removeDecks(ids: [deckId])
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }
}
