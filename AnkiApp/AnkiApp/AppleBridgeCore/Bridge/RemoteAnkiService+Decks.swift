import Foundation

extension RemoteAnkiService {
    public func getDeck(id: Int64) async throws -> Anki_Decks_Deck {
        var req = Anki_Decks_DeckId()
        req.did = id
        return try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.getDeck,
            input: req
        )
    }

    public func updateDeck(deck: Anki_Decks_Deck) async throws -> Anki_Collection_OpChanges {
        try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.updateDeck,
            input: deck
        )
    }

    public func updateDeckConfigs(request: Anki_DeckConfig_UpdateDeckConfigsRequest) async throws
        -> Anki_Collection_OpChanges {
        try await command(
            service: ServiceIndex.deckConfig,
            method: DeckConfigMethod.updateDeckConfigs,
            input: request
        )
    }
}
