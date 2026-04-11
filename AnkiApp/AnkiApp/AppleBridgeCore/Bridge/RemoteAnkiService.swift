import Foundation
import SwiftProtobuf

public actor RemoteAnkiService: AnkiServiceProtocol {
    private let transport: any BackendCommandTransport

    public init(
        sessionProvider: any RemoteSessionProviding,
        session: URLSession = .shared
    ) {
        transport = RemoteHTTPCommandTransport(sessionProvider: sessionProvider, session: session)
    }

    public init(transport: any BackendCommandTransport) {
        self.transport = transport
    }

    private func command<Output: SwiftProtobuf.Message>(
        service: UInt32,
        method: UInt32,
        input: some SwiftProtobuf.Message
    ) async throws -> Output {
        try await transport.sendCommand(service: service, method: method, input: input)
    }

    public func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = path
        req.mediaFolderPath = mediaFolder
        req.mediaDbPath = mediaDb
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.openCollection,
            input: req
        )
    }

    public func closeCollection(downgrade: Bool) async throws {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgrade
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.closeCollection,
            input: req
        )
    }

    public func getUndoStatus() async throws -> Anki_Collection_UndoStatus {
        try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.getUndoStatus,
            input: Anki_Generic_Empty()
        )
    }

    public func undo() async throws -> Anki_Collection_OpChangesAfterUndo {
        try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.undo,
            input: Anki_Generic_Empty()
        )
    }

    public func redo() async throws -> Anki_Collection_OpChangesAfterUndo {
        try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.redo,
            input: Anki_Generic_Empty()
        )
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

    public func searchCards(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        var req = Anki_Search_SearchRequest()
        req.search = search
        req.order = order
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.searchCards,
            input: req
        )
    }

    public func searchNotes(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        var req = Anki_Search_SearchRequest()
        req.search = search
        req.order = order
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.searchNotes,
            input: req
        )
    }

    public func allBrowserColumns() async throws -> Anki_Search_BrowserColumns {
        try await command(
            service: ServiceIndex.search,
            method: SearchMethod.allBrowserColumns,
            input: Anki_Generic_Empty()
        )
    }

    public func browserRowForId(id: Int64) async throws -> Anki_Search_BrowserRow {
        var req = Anki_Generic_Int64()
        req.val = id
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.browserRowForId,
            input: req
        )
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

    public func findAndReplace(
        nids: [Int64],
        search: String,
        replacement: String,
        regex: Bool,
        matchCase: Bool,
        fieldName: String
    ) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Search_FindAndReplaceRequest()
        req.nids = nids
        req.search = search
        req.replacement = replacement
        req.regex = regex
        req.matchCase = matchCase
        req.fieldName = fieldName
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.findAndReplace,
            input: req
        )
    }

    public func setActiveBrowserColumns(columns: [String]) async throws {
        var req = Anki_Generic_StringList()
        req.vals = columns
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.search,
            method: SearchMethod.setActiveBrowserColumns,
            input: req
        )
    }

    public func getGraphs(search: String, days: UInt32) async throws -> Anki_Stats_GraphsResponse {
        var req = Anki_Stats_GraphsRequest()
        req.search = search
        req.days = days
        return try await command(
            service: ServiceIndex.stats,
            method: StatsMethod.graphs,
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

    public func syncLogin(username: String, password: String) async throws -> Anki_Sync_SyncAuth {
        var req = Anki_Sync_SyncLoginRequest()
        req.username = username
        req.password = password
        return try await command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncLogin,
            input: req
        )
    }

    public func syncStatus(auth: Anki_Sync_SyncAuth) async throws -> Anki_Sync_SyncStatusResponse {
        try await command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncStatus,
            input: auth
        )
    }

    public func syncCollection(auth: Anki_Sync_SyncAuth, syncMedia: Bool) async throws -> Anki_Sync_SyncCollectionResponse {
        var req = Anki_Sync_SyncCollectionRequest()
        req.auth = auth
        req.syncMedia = syncMedia
        return try await command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncCollection,
            input: req
        )
    }

    public func fullUploadOrDownload(auth: Anki_Sync_SyncAuth, upload: Bool, serverUsn: Int32?) async throws {
        var req = Anki_Sync_FullUploadOrDownloadRequest()
        req.auth = auth
        req.upload = upload
        if let serverUsn {
            req.serverUsn = serverUsn
        }
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.sync,
            method: SyncMethod.fullUploadOrDownload,
            input: req
        )
    }

    public func syncMedia(auth: Anki_Sync_SyncAuth) async throws {
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncMedia,
            input: auth
        )
    }

    public func setBrowserTableNotesMode(_ enabled: Bool) async throws {
        var req = Anki_Config_SetConfigBoolRequest()
        req.key = .browserTableShowNotesMode
        req.value = enabled
        req.undoable = false
        let _: Anki_Collection_OpChanges = try await command(
            service: ServiceIndex.config,
            method: ConfigMethod.setConfigBool,
            input: req
        )
    }

    public func getPreferences() async throws -> Anki_Config_Preferences {
        try await command(
            service: ServiceIndex.config,
            method: ConfigMethod.getPreferences,
            input: Anki_Generic_Empty()
        )
    }

    public func setPreferences(prefs: Anki_Config_Preferences) async throws {
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.config,
            method: ConfigMethod.setPreferences,
            input: prefs
        )
    }

    public func getCardStats(cardId: Int64) async throws -> Anki_Stats_CardStatsResponse {
        var req = Anki_Cards_CardId()
        req.cid = cardId
        return try await command(
            service: ServiceIndex.stats,
            method: StatsMethod.cardStats,
            input: req
        )
    }
}
