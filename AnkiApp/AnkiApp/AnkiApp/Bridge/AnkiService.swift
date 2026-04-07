// swiftlint:disable type_body_length
actor AnkiService: AnkiServiceProtocol {
    private let backend: AnkiBackend

    init(langs: [String] = ["en"]) throws {
        backend = try AnkiBackend(preferredLangs: langs)
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

    func searchNotes(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        var req = Anki_Search_SearchRequest()
        req.search = search
        req.order = order
        return try backend.command(
            service: ServiceIndex.search,
            method: SearchMethod.searchNotes,
            input: req
        )
    }

    func allBrowserColumns() async throws -> Anki_Search_BrowserColumns {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.search,
            method: SearchMethod.allBrowserColumns,
            input: req
        )
    }

    func removeNotes(noteIds: [Int64], cardIds: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Notes_RemoveNotesRequest()
        req.noteIds = noteIds
        req.cardIds = cardIds
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.removeNotes,
            input: req
        )
    }

    func findAndReplace(
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
        return try backend.command(
            service: ServiceIndex.search,
            method: SearchMethod.findAndReplace,
            input: req
        )
    }

    func setActiveBrowserColumns(columns: [String]) async throws {
        var req = Anki_Generic_StringList()
        req.vals = columns
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.search,
            method: SearchMethod.setActiveBrowserColumns,
            input: req
        )
    }

    func setDueDate(cardIds: [Int64], days: String) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_SetDueDateRequest()
        req.cardIds = cardIds
        req.days = days
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.setDueDate,
            input: req
        )
    }

    func scheduleCardsAsNew(cardIds: [Int64], log: Bool, restorePosition: Bool,
                            resetCounts: Bool) async throws -> Anki_Collection_OpChanges
    {
        var req = Anki_Scheduler_ScheduleCardsAsNewRequest()
        req.cardIds = cardIds
        req.log = log
        req.restorePosition = restorePosition
        req.resetCounts = resetCounts
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.scheduleCardsAsNew,
            input: req
        )
    }

    func addNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Tags_NoteIdsAndTagsRequest()
        req.noteIds = noteIds
        req.tags = tags
        return try backend.command(
            service: ServiceIndex.tags,
            method: TagsMethod.addNoteTags,
            input: req
        )
    }

    func removeNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Tags_NoteIdsAndTagsRequest()
        req.noteIds = noteIds
        req.tags = tags
        return try backend.command(
            service: ServiceIndex.tags,
            method: TagsMethod.removeNoteTags,
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
        try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.clozeNumbersInNote,
            input: note
        )
    }

    func noteFieldsCheck(note: Anki_Notes_Note) async throws -> Anki_Notes_NoteFieldsCheckResponse {
        try backend.command(
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
        try backend.command(
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
        -> Anki_Collection_OpChanges
    {
        try backend.command(
            service: ServiceIndex.deckConfig,
            method: DeckConfigMethod.updateDeckConfigs,
            input: request
        )
    }

    func addMediaFile(desiredName: String, data: Data) async throws -> String {
        var req = Anki_Media_AddMediaFileRequest()
        req.desiredName = desiredName
        req.data = data
        let response: Anki_Generic_String = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.addMediaFile,
            input: req
        )
        return response.val
    }

    func buryOrSuspendCards(
        cardIds: [Int64],
        noteIds: [Int64],
        mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode
    ) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
        req.cardIds = cardIds
        req.noteIds = noteIds
        req.mode = mode
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.buryOrSuspendCards,
            input: req
        )
    }

    func setFlag(cardIds: [Int64], flag: UInt32) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Cards_SetFlagRequest()
        req.cardIds = cardIds
        req.flag = flag
        return try backend.command(
            service: ServiceIndex.cards,
            method: CardsMethod.setFlag,
            input: req
        )
    }

    func importAnkiPackage(path: String,
                           options: Anki_ImportExport_ImportAnkiPackageOptions) async throws
        -> Anki_ImportExport_ImportResponse
    {
        var req = Anki_ImportExport_ImportAnkiPackageRequest()
        req.packagePath = path
        req.options = options
        return try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.importAnkiPackage,
            input: req
        )
    }

    func exportAnkiPackage(
        outPath: String,
        options: Anki_ImportExport_ExportAnkiPackageOptions,
        limit: Anki_ImportExport_ExportLimit
    ) async throws -> UInt32 {
        var req = Anki_ImportExport_ExportAnkiPackageRequest()
        req.outPath = outPath
        req.options = options
        req.limit = limit
        let response: Anki_Generic_UInt32 = try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.exportAnkiPackage,
            input: req
        )
        return response.val
    }

    func getCsvMetadata(
        path: String,
        delimiter: Anki_ImportExport_CsvMetadata.Delimiter?,
        notetypeId: Int64?,
        deckId: Int64?,
        isHtml: Bool?
    ) async throws -> Anki_ImportExport_CsvMetadata {
        var req = Anki_ImportExport_CsvMetadataRequest()
        req.path = path
        if let delimiter { req.delimiter = delimiter }
        if let notetypeId { req.notetypeID = notetypeId }
        if let deckId { req.deckID = deckId }
        if let isHtml { req.isHTML = isHtml }
        return try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.getCsvMetadata,
            input: req
        )
    }

    func importCsv(path: String,
                   metadata: Anki_ImportExport_CsvMetadata) async throws -> Anki_ImportExport_ImportResponse
    {
        var req = Anki_ImportExport_ImportCsvRequest()
        req.path = path
        req.metadata = metadata
        return try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.importCsv,
            input: req
        )
    }

    func checkMedia() async throws -> Anki_Media_CheckMediaResponse {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.checkMedia,
            input: req
        )
    }

    func trashMediaFiles(filenames: [String]) async throws {
        var req = Anki_Media_TrashMediaFilesRequest()
        req.fnames = filenames
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.trashMediaFiles,
            input: req
        )
    }

    func emptyTrash() async throws {
        let req = Anki_Generic_Empty()
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.emptyTrash,
            input: req
        )
    }

    func restoreTrash() async throws {
        let req = Anki_Generic_Empty()
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.restoreTrash,
            input: req
        )
    }

    func addNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChangesWithId {
        try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.addNotetype,
            input: notetype
        )
    }

    func updateNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChanges {
        try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.updateNotetype,
            input: notetype
        )
    }

    func removeNotetype(id: Int64) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = id
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.removeNotetype,
            input: req
        )
    }

    func getNotetypeNamesAndCounts() async throws -> Anki_Notetypes_NotetypeUseCounts {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetypeNamesAndCounts,
            input: req
        )
    }

    func getImageForOcclusion(path: String) async throws -> Anki_ImageOcclusion_GetImageForOcclusionResponse {
        var req = Anki_ImageOcclusion_GetImageForOcclusionRequest()
        req.path = path
        return try backend.command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.getImageForOcclusion,
            input: req
        )
    }

    func addImageOcclusionNote(request: Anki_ImageOcclusion_AddImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges
    {
        try backend.command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.addImageOcclusionNote,
            input: request
        )
    }

    func updateImageOcclusionNote(request: Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges
    {
        try backend.command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.updateImageOcclusionNote,
            input: request
        )
    }

    func customStudy(request: Anki_Scheduler_CustomStudyRequest) async throws -> Anki_Collection_OpChanges {
        try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.customStudy,
            input: request
        )
    }

    func customStudyDefaults(deckId: Int64) async throws -> Anki_Scheduler_CustomStudyDefaultsResponse {
        var req = Anki_Scheduler_CustomStudyDefaultsRequest()
        req.deckID = deckId
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.customStudyDefaults,
            input: req
        )
    }

    func emptyFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.emptyFilteredDeck,
            input: req
        )
    }

    func rebuildFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.rebuildFilteredDeck,
            input: req
        )
    }

    func createBackup(backupFolder: String, force: Bool, waitForCompletion: Bool) async throws -> Bool {
        var req = Anki_Collection_CreateBackupRequest()
        req.backupFolder = backupFolder
        req.force = force
        req.waitForCompletion = waitForCompletion
        let response: Anki_Generic_Bool = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.createBackup,
            input: req
        )
        return response.val
    }

    func awaitBackupCompletion() async throws -> Bool {
        let req = Anki_Generic_Empty()
        let response: Anki_Generic_Bool = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.awaitBackupCompletion,
            input: req
        )
        return response.val
    }

    func getPreferences() async throws -> Anki_Config_Preferences {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.config,
            method: ConfigMethod.getPreferences,
            input: req
        )
    }

    func setPreferences(prefs: Anki_Config_Preferences) async throws {
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.config,
            method: ConfigMethod.setPreferences,
            input: prefs
        )
    }

    func compareAnswer(expected: String, provided: String) async throws -> String {
        var req = Anki_CardRendering_CompareAnswerRequest()
        req.expected = expected
        req.provided = provided
        let response: Anki_Generic_String = try backend.command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.compareAnswer,
            input: req
        )
        return response.val
    }

    func getCardStats(cardId: Int64) async throws -> Anki_Stats_CardStatsResponse {
        var req = Anki_Cards_CardId()
        req.cid = cardId
        return try backend.command(
            service: ServiceIndex.stats,
            method: StatsMethod.cardStats,
            input: req
        )
    }
}
