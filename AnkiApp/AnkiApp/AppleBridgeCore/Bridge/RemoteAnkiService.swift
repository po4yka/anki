import Foundation
import SwiftProtobuf

public actor RemoteAnkiService: AnkiServiceProtocol {
    let transport: any BackendCommandTransport

    public init(
        sessionProvider: any RemoteSessionProviding,
        session: URLSession = .shared
    ) {
        transport = RemoteHTTPCommandTransport(sessionProvider: sessionProvider, session: session)
    }

    public init(transport: any BackendCommandTransport) {
        self.transport = transport
    }

    func command<Output: SwiftProtobuf.Message>(
        service: UInt32,
        method: UInt32,
        input: some SwiftProtobuf.Message
    ) async throws -> Output {
        try await transport.sendCommand(service: service, method: method, input: input)
    }

    public func getDeckTree(now: Int64) async throws -> Anki_Decks_DeckTreeNode {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = now
        return try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.deckTree,
            input: req
        )
    }

    public func setCurrentDeck(deckId: Int64) async throws {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        let _: Anki_Collection_OpChanges = try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.setCurrentDeck,
            input: req
        )
    }

    public func newDeck() async throws -> Anki_Decks_Deck {
        try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.newDeck,
            input: Anki_Generic_Empty()
        )
    }

    public func addDeck(deck: Anki_Decks_Deck) async throws -> Anki_Collection_OpChangesWithId {
        try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.addDeck,
            input: deck
        )
    }

    public func removeDecks(ids: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Decks_DeckIds()
        req.dids = ids
        return try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.removeDecks,
            input: req
        )
    }

    public func renameDeck(deckId: Int64, newName: String) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Decks_RenameDeckRequest()
        req.deckID = deckId
        req.newName = newName
        return try await command(
            service: ServiceIndex.decks,
            method: DecksMethod.renameDeck,
            input: req
        )
    }

    public func getQueuedCards(fetchLimit: UInt32) async throws -> Anki_Scheduler_QueuedCards {
        var req = Anki_Scheduler_GetQueuedCardsRequest()
        req.fetchLimit = fetchLimit
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.getQueuedCards,
            input: req
        )
    }

    // Stable bridge signature; wrapping this in a parameter object would not simplify the call sites.
    // swiftlint:disable:next function_parameter_count
    public func answerCard(
        cardId: Int64,
        rating: Anki_Scheduler_CardAnswer.Rating,
        currentState: Anki_Scheduler_SchedulingState,
        newState: Anki_Scheduler_SchedulingState,
        answeredAtMillis: Int64,
        millisecondsTaken: UInt32
    ) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_CardAnswer()
        req.cardID = cardId
        req.rating = rating
        req.currentState = currentState
        req.newState = newState
        req.answeredAtMillis = answeredAtMillis
        req.millisecondsTaken = millisecondsTaken
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.answerCard,
            input: req
        )
    }

    public func buryOrSuspendCards(
        cardIds: [Int64],
        noteIds: [Int64],
        mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode
    ) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
        req.cardIds = cardIds
        req.noteIds = noteIds
        req.mode = mode
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.buryOrSuspendCards,
            input: req
        )
    }

    public func scheduleCardsAsNew(cardIds: [Int64], log: Bool, restorePosition: Bool, resetCounts: Bool) async throws
        -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_ScheduleCardsAsNewRequest()
        req.cardIds = cardIds
        req.log = log
        req.restorePosition = restorePosition
        req.resetCounts = resetCounts
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.scheduleCardsAsNew,
            input: req
        )
    }

    public func setDueDate(cardIds: [Int64], days: String) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_SetDueDateRequest()
        req.cardIds = cardIds
        req.days = days
        return try await command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.setDueDate,
            input: req
        )
    }

    public func renderExistingCard(cardId: Int64) async throws -> Anki_CardRendering_RenderCardResponse {
        var req = Anki_CardRendering_RenderExistingCardRequest()
        req.cardID = cardId
        return try await command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.renderExistingCard,
            input: req
        )
    }

    public func compareAnswer(expected: String, provided: String, combining: Bool) async throws -> String {
        var req = Anki_CardRendering_CompareAnswerRequest()
        req.expected = expected
        req.provided = provided
        req.combining = combining
        let response: Anki_Generic_String = try await command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.compareAnswer,
            input: req
        )
        return response.val
    }

    public func removeNotes(noteIds: [Int64], cardIds: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Notes_RemoveNotesRequest()
        req.noteIds = noteIds
        req.cardIds = cardIds
        return try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.removeNotes,
            input: req
        )
    }

    public func getCard(id: Int64) async throws -> Anki_Cards_Card {
        var req = Anki_Cards_CardId()
        req.cid = id
        return try await command(
            service: ServiceIndex.cards,
            method: CardsMethod.getCard,
            input: req
        )
    }

    public func setFlag(cardIds: [Int64], flag: UInt32) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Cards_SetFlagRequest()
        req.cardIds = cardIds
        req.flag = flag
        return try await command(
            service: ServiceIndex.cards,
            method: CardsMethod.setFlag,
            input: req
        )
    }

    public func addNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Tags_NoteIdsAndTagsRequest()
        req.noteIds = noteIds
        req.tags = tags
        return try await command(
            service: ServiceIndex.tags,
            method: TagsMethod.addNoteTags,
            input: req
        )
    }

    public func removeNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Tags_NoteIdsAndTagsRequest()
        req.noteIds = noteIds
        req.tags = tags
        return try await command(
            service: ServiceIndex.tags,
            method: TagsMethod.removeNoteTags,
            input: req
        )
    }

    public func cardsOfNote(noteId: Int64) async throws -> [Int64] {
        var req = Anki_Notes_NoteId()
        req.nid = noteId
        let response: Anki_Cards_CardIds = try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.cardsOfNote,
            input: req
        )
        return response.cids
    }

    public func getDeckConfigsForUpdate(deckId: Int64) async throws -> Anki_DeckConfig_DeckConfigsForUpdate {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try await command(
            service: ServiceIndex.deckConfig,
            method: DeckConfigMethod.getDeckConfigsForUpdate,
            input: req
        )
    }
}
