import Foundation

protocol AnkiServiceProtocol: Sendable {
    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws
    func closeCollection(downgrade: Bool) async throws
    func getDeckTree(now: Int64) async throws -> Anki_Decks_DeckTreeNode
    func getQueuedCards(fetchLimit: UInt32) async throws -> Anki_Scheduler_QueuedCards
    // swiftlint:disable:next function_parameter_count
    func answerCard(
        cardId: Int64,
        rating: Anki_Scheduler_CardAnswer.Rating,
        currentState: Anki_Scheduler_SchedulingState,
        newState: Anki_Scheduler_SchedulingState,
        answeredAtMillis: Int64,
        millisecondsTaken: UInt32
    ) async throws -> Anki_Collection_OpChanges
    func renderExistingCard(cardId: Int64) async throws -> Anki_CardRendering_RenderCardResponse
    func getNote(id: Int64) async throws -> Anki_Notes_Note
    func addNote(note: Anki_Notes_Note, deckId: Int64) async throws -> Anki_Notes_AddNoteResponse
    func searchCards(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse
    func searchNotes(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse
    func allBrowserColumns() async throws -> Anki_Search_BrowserColumns
    func browserRowForId(id: Int64) async throws -> Anki_Search_BrowserRow
    func removeNotes(noteIds: [Int64], cardIds: [Int64]) async throws -> Anki_Collection_OpChangesWithCount
    // swiftlint:disable:next function_parameter_count
    func findAndReplace(
        nids: [Int64],
        search: String,
        replacement: String,
        regex: Bool,
        matchCase: Bool,
        fieldName: String
    ) async throws -> Anki_Collection_OpChangesWithCount
    func setActiveBrowserColumns(columns: [String]) async throws
    func setDueDate(cardIds: [Int64], days: String) async throws -> Anki_Collection_OpChanges
    func scheduleCardsAsNew(cardIds: [Int64], log: Bool, restorePosition: Bool, resetCounts: Bool) async throws
        -> Anki_Collection_OpChanges
    func addNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount
    func removeNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount
    func getGraphs(search: String, days: UInt32) async throws -> Anki_Stats_GraphsResponse
    func getNotetypeNames() async throws -> Anki_Notetypes_NotetypeNames
    func getNotetype(id: Int64) async throws -> Anki_Notetypes_Notetype
    func allTags() async throws -> Anki_Generic_StringList
    func getCard(id: Int64) async throws -> Anki_Cards_Card
    func updateNotes(notes: [Anki_Notes_Note]) async throws -> Anki_Collection_OpChanges
    func getUndoStatus() async throws -> Anki_Collection_UndoStatus
    func undo() async throws -> Anki_Collection_OpChangesAfterUndo
    func redo() async throws -> Anki_Collection_OpChangesAfterUndo
    func extractAvTags(text: String, questionSide: Bool) async throws -> Anki_CardRendering_ExtractAvTagsResponse
    func clozeNumbersInNote(note: Anki_Notes_Note) async throws -> Anki_Notes_ClozeNumbersInNoteResponse
    func noteFieldsCheck(note: Anki_Notes_Note) async throws -> Anki_Notes_NoteFieldsCheckResponse
    func syncLogin(username: String, password: String) async throws -> Anki_Sync_SyncAuth
    func syncStatus(auth: Anki_Sync_SyncAuth) async throws -> Anki_Sync_SyncStatusResponse
    func syncCollection(auth: Anki_Sync_SyncAuth, syncMedia: Bool) async throws -> Anki_Sync_SyncCollectionResponse
    func fullUploadOrDownload(auth: Anki_Sync_SyncAuth, upload: Bool, serverUsn: Int32?) async throws
    func syncMedia(auth: Anki_Sync_SyncAuth) async throws
    func newDeck() async throws -> Anki_Decks_Deck
    func addDeck(deck: Anki_Decks_Deck) async throws -> Anki_Collection_OpChangesWithId
    func getDeck(id: Int64) async throws -> Anki_Decks_Deck
    func updateDeck(deck: Anki_Decks_Deck) async throws -> Anki_Collection_OpChanges
    func removeDecks(ids: [Int64]) async throws -> Anki_Collection_OpChangesWithCount
    func renameDeck(deckId: Int64, newName: String) async throws -> Anki_Collection_OpChanges
    func getDeckConfigsForUpdate(deckId: Int64) async throws -> Anki_DeckConfig_DeckConfigsForUpdate
    func updateDeckConfigs(request: Anki_DeckConfig_UpdateDeckConfigsRequest) async throws -> Anki_Collection_OpChanges
    func addMediaFile(desiredName: String, data: Data) async throws -> String
    func buryOrSuspendCards(
        cardIds: [Int64],
        noteIds: [Int64],
        mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode
    ) async throws -> Anki_Collection_OpChangesWithCount
    func setFlag(cardIds: [Int64], flag: UInt32) async throws -> Anki_Collection_OpChangesWithCount
    func importAnkiPackage(path: String, options: Anki_ImportExport_ImportAnkiPackageOptions) async throws
        -> Anki_ImportExport_ImportResponse
    func exportAnkiPackage(
        outPath: String,
        options: Anki_ImportExport_ExportAnkiPackageOptions,
        limit: Anki_ImportExport_ExportLimit
    ) async throws -> UInt32
    func getCsvMetadata(
        path: String,
        delimiter: Anki_ImportExport_CsvMetadata.Delimiter?,
        notetypeId: Int64?,
        deckId: Int64?,
        isHtml: Bool?
    ) async throws -> Anki_ImportExport_CsvMetadata
    func importCsv(path: String, metadata: Anki_ImportExport_CsvMetadata) async throws
        -> Anki_ImportExport_ImportResponse
    func checkMedia() async throws -> Anki_Media_CheckMediaResponse
    func trashMediaFiles(filenames: [String]) async throws
    func emptyTrash() async throws
    func restoreTrash() async throws
    func addNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChangesWithId
    func updateNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChanges
    func removeNotetype(id: Int64) async throws -> Anki_Collection_OpChanges
    func getNotetypeNamesAndCounts() async throws -> Anki_Notetypes_NotetypeUseCounts
    func getImageForOcclusion(path: String) async throws -> Anki_ImageOcclusion_GetImageForOcclusionResponse
    func addImageOcclusionNote(request: Anki_ImageOcclusion_AddImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges
    func updateImageOcclusionNote(request: Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges
    func customStudy(request: Anki_Scheduler_CustomStudyRequest) async throws -> Anki_Collection_OpChanges
    func customStudyDefaults(deckId: Int64) async throws -> Anki_Scheduler_CustomStudyDefaultsResponse
    func emptyFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChanges
    func rebuildFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChangesWithCount
    func createBackup(backupFolder: String, force: Bool, waitForCompletion: Bool) async throws -> Bool
    func awaitBackupCompletion() async throws -> Bool
    func getPreferences() async throws -> Anki_Config_Preferences
    func setPreferences(prefs: Anki_Config_Preferences) async throws
    func compareAnswer(expected: String, provided: String) async throws -> String
    func getCardStats(cardId: Int64) async throws -> Anki_Stats_CardStatsResponse
}
