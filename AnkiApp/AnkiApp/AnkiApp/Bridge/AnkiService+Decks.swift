// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
import Foundation

extension AnkiService {
    func getDeckTree(now: Int64) async throws -> Anki_Decks_DeckTreeNode {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = now
        return try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.deckTree,
            input: req
        )
    }

    func newDeck() async throws -> Anki_Decks_Deck {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.newDeck,
            input: req
        )
    }

    func addDeck(deck: Anki_Decks_Deck) async throws -> Anki_Collection_OpChangesWithId {
        try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.addDeck,
            input: deck
        )
    }

    func getDeck(id: Int64) async throws -> Anki_Decks_Deck {
        var req = Anki_Decks_DeckId()
        req.did = id
        return try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.getDeck,
            input: req
        )
    }

    func updateDeck(deck: Anki_Decks_Deck) async throws -> Anki_Collection_OpChanges {
        try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.updateDeck,
            input: deck
        )
    }

    func removeDecks(ids: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Decks_DeckIds()
        req.dids = ids
        return try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.removeDecks,
            input: req
        )
    }

    func renameDeck(deckId: Int64, newName: String) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Decks_RenameDeckRequest()
        req.deckID = deckId
        req.newName = newName
        return try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.renameDeck,
            input: req
        )
    }

    func setCurrentDeck(deckId: Int64) async throws {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        let _: Anki_Collection_OpChanges = try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.setCurrentDeck,
            input: req
        )
    }

    func getDeckConfigsForUpdate(deckId: Int64) async throws -> Anki_DeckConfig_DeckConfigsForUpdate {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try backend.command(
            service: ServiceIndex.deckConfig,
            method: DeckConfigMethod.getDeckConfigsForUpdate,
            input: req
        )
    }

    func updateDeckConfigs(request: Anki_DeckConfig_UpdateDeckConfigsRequest) async throws
        -> Anki_Collection_OpChanges {
        try backend.command(
            service: ServiceIndex.deckConfig,
            method: DeckConfigMethod.updateDeckConfigs,
            input: request
        )
    }
}
#endif
