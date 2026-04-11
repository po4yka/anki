import Foundation

extension RemoteAnkiService {
    public func customStudy(request: Anki_Scheduler_CustomStudyRequest) async throws -> Anki_Collection_OpChanges {
        try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.customStudy,
            input: request
        )
    }

    public func customStudyDefaults(deckId: Int64) async throws -> Anki_Scheduler_CustomStudyDefaultsResponse {
        var req = Anki_Scheduler_CustomStudyDefaultsRequest()
        req.deckID = deckId
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.customStudyDefaults,
            input: req
        )
    }

    public func emptyFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.emptyFilteredDeck,
            input: req
        )
    }

    public func rebuildFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.rebuildFilteredDeck,
            input: req
        )
    }
}
