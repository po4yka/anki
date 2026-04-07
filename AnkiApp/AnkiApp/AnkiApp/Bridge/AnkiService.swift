actor AnkiService: AnkiServiceProtocol {
    private let backend: AnkiBackend

    init(langs: [String] = ["en"]) throws {
        self.backend = try AnkiBackend(preferredLangs: langs)
    }

    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = path
        req.mediaFolderPath = mediaFolder
        req.mediaDbPath = mediaDb
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.openCollection,
            input: req
        )
    }

    func closeCollection(downgrade: Bool) async throws {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgrade
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.closeCollection,
            input: req
        )
    }

    func getCard(id: Int64) async throws -> Anki_Cards_Card {
        var req = Anki_Cards_CardId()
        req.cid = id
        return try backend.command(
            service: ServiceIndex.cards,
            method: CardsMethod.getCard,
            input: req
        )
    }

    func getDeckTree(now: Int64) async throws -> Anki_Decks_DeckTreeNode {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = now
        return try backend.command(
            service: ServiceIndex.decks,
            method: DecksMethod.deckTree,
            input: req
        )
    }

    func getQueuedCards(fetchLimit: UInt32) async throws -> Anki_Scheduler_QueuedCards {
        var req = Anki_Scheduler_GetQueuedCardsRequest()
        req.fetchLimit = fetchLimit
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.getQueuedCards,
            input: req
        )
    }

    func answerCard(
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
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.answerCard,
            input: req
        )
    }

    func renderExistingCard(cardId: Int64) async throws -> Anki_CardRendering_RenderCardResponse {
        var req = Anki_CardRendering_RenderExistingCardRequest()
        req.cardID = cardId
        return try backend.command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.renderExistingCard,
            input: req
        )
    }

    func getNote(id: Int64) async throws -> Anki_Notes_Note {
        var req = Anki_Notes_NoteId()
        req.nid = id
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.getNote,
            input: req
        )
    }

    func addNote(note: Anki_Notes_Note, deckId: Int64) async throws -> Anki_Notes_AddNoteResponse {
        var req = Anki_Notes_AddNoteRequest()
        req.note = note
        req.deckID = deckId
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.addNote,
            input: req
        )
    }

    func searchCards(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        var req = Anki_Search_SearchRequest()
        req.search = search
        req.order = order
        return try backend.command(
            service: ServiceIndex.search,
            method: SearchMethod.searchCards,
            input: req
        )
    }

    func browserRowForId(id: Int64) async throws -> Anki_Search_BrowserRow {
        var req = Anki_Generic_Int64()
        req.val = id
        return try backend.command(
            service: ServiceIndex.search,
            method: SearchMethod.browserRowForId,
            input: req
        )
    }

    func getGraphs(search: String, days: UInt32) async throws -> Anki_Stats_GraphsResponse {
        var req = Anki_Stats_GraphsRequest()
        req.search = search
        req.days = days
        return try backend.command(
            service: ServiceIndex.stats,
            method: StatsMethod.graphs,
            input: req
        )
    }

    func getNotetypeNames() async throws -> Anki_Notetypes_NotetypeNames {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetypeNames,
            input: req
        )
    }

    func allTags() async throws -> Anki_Generic_StringList {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.tags,
            method: TagsMethod.allTags,
            input: req
        )
    }

    func updateNotes(notes: [Anki_Notes_Note]) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notes_UpdateNotesRequest()
        req.notes = notes
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.updateNotes,
            input: req
        )
    }

    func getNotetype(id: Int64) async throws -> Anki_Notetypes_Notetype {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = id
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetype,
            input: req
        )
    }

    func getUndoStatus() async throws -> Anki_Collection_UndoStatus {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.getUndoStatus,
            input: req
        )
    }

    func undo() async throws -> Anki_Collection_OpChangesAfterUndo {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.undo,
            input: req
        )
    }

    func redo() async throws -> Anki_Collection_OpChangesAfterUndo {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.redo,
            input: req
        )
    }

    func extractAvTags(text: String, questionSide: Bool) async throws -> Anki_CardRendering_ExtractAvTagsResponse {
        var req = Anki_CardRendering_ExtractAvTagsRequest()
        req.text = text
        req.questionSide = questionSide
        return try backend.command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.extractAvTags,
            input: req
        )
    }

    func clozeNumbersInNote(note: Anki_Notes_Note) async throws -> Anki_Notes_ClozeNumbersInNoteResponse {
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.clozeNumbersInNote,
            input: note
        )
    }

    func noteFieldsCheck(note: Anki_Notes_Note) async throws -> Anki_Notes_NoteFieldsCheckResponse {
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.noteFieldsCheck,
            input: note
        )
    }

    func syncLogin(username: String, password: String) async throws -> Anki_Sync_SyncAuth {
        var req = Anki_Sync_SyncLoginRequest()
        req.username = username
        req.password = password
        return try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncLogin,
            input: req
        )
    }

    func syncStatus(auth: Anki_Sync_SyncAuth) async throws -> Anki_Sync_SyncStatusResponse {
        return try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncStatus,
            input: auth
        )
    }

    func syncCollection(auth: Anki_Sync_SyncAuth, syncMedia: Bool) async throws -> Anki_Sync_SyncCollectionResponse {
        var req = Anki_Sync_SyncCollectionRequest()
        req.auth = auth
        req.syncMedia = syncMedia
        return try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncCollection,
            input: req
        )
    }

    func fullUploadOrDownload(auth: Anki_Sync_SyncAuth, upload: Bool, serverUsn: Int32?) async throws {
        var req = Anki_Sync_FullUploadOrDownloadRequest()
        req.auth = auth
        req.upload = upload
        if let serverUsn {
            req.serverUsn = serverUsn
        }
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.fullUploadOrDownload,
            input: req
        )
    }

    func syncMedia(auth: Anki_Sync_SyncAuth) async throws {
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncMedia,
            input: auth
        )
    }
}
