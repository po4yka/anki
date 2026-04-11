import Foundation

// swiftlint:disable file_length

public protocol AnkiServiceProtocol: Sendable {
    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws
    func closeCollection(downgrade: Bool) async throws
    func newNote(notetypeId: Int64) async throws -> Anki_Notes_Note
    func defaultsForAdding(homeDeckOfCurrentReviewCard: Int64) async throws -> Anki_Notes_DeckAndNotetype
    func getDeckTree(now: Int64) async throws -> Anki_Decks_DeckTreeNode
    func setCurrentDeck(deckId: Int64) async throws
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
    // Stable bridge signature; wrapping this in a parameter object would not simplify the call sites.
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
    func cardsOfNote(noteId: Int64) async throws -> [Int64]
    func addNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChangesWithId
    func updateNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChanges
    func removeNotetype(id: Int64) async throws -> Anki_Collection_OpChanges
    func getNotetypeNamesAndCounts() async throws -> Anki_Notetypes_NotetypeUseCounts
    func getImageForOcclusion(path: String) async throws -> Anki_ImageOcclusion_GetImageForOcclusionResponse
    func getImageOcclusionNote(noteId: Int64) async throws
        -> Anki_ImageOcclusion_GetImageOcclusionNoteResponse
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
    func setBrowserTableNotesMode(_ enabled: Bool) async throws
    func getPreferences() async throws -> Anki_Config_Preferences
    func setPreferences(prefs: Anki_Config_Preferences) async throws
    func compareAnswer(expected: String, provided: String, combining: Bool) async throws -> String
    func getCardStats(cardId: Int64) async throws -> Anki_Stats_CardStatsResponse
}

extension AnkiServiceProtocol {
    private func unavailableError() -> AnkiError {
        .message("The Anki backend is unavailable.")
    }

    public func openCollection(path _: String, mediaFolder _: String, mediaDb _: String) async throws {
        throw unavailableError()
    }

    public func closeCollection(downgrade _: Bool) async throws {
        throw unavailableError()
    }

    public func newNote(notetypeId _: Int64) async throws -> Anki_Notes_Note {
        throw unavailableError()
    }

    public func defaultsForAdding(homeDeckOfCurrentReviewCard _: Int64) async throws -> Anki_Notes_DeckAndNotetype {
        throw unavailableError()
    }

    public func getDeckTree(now _: Int64) async throws -> Anki_Decks_DeckTreeNode {
        throw unavailableError()
    }

    public func setCurrentDeck(deckId _: Int64) async throws {
        throw unavailableError()
    }

    public func getQueuedCards(fetchLimit _: UInt32) async throws -> Anki_Scheduler_QueuedCards {
        throw unavailableError()
    }

    // Stable bridge signature; wrapping this in a parameter object would not simplify the call sites.
    // swiftlint:disable:next function_parameter_count
    public func answerCard(
        cardId _: Int64,
        rating _: Anki_Scheduler_CardAnswer.Rating,
        currentState _: Anki_Scheduler_SchedulingState,
        newState _: Anki_Scheduler_SchedulingState,
        answeredAtMillis _: Int64,
        millisecondsTaken _: UInt32
    ) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func renderExistingCard(cardId _: Int64) async throws
        -> Anki_CardRendering_RenderCardResponse {
        throw unavailableError()
    }

    public func getNote(id _: Int64) async throws -> Anki_Notes_Note {
        throw unavailableError()
    }

    public func addNote(note _: Anki_Notes_Note,
                 deckId _: Int64) async throws -> Anki_Notes_AddNoteResponse {
        throw unavailableError()
    }

    public func searchCards(search _: String, order _: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        throw unavailableError()
    }

    public func searchNotes(search _: String, order _: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        throw unavailableError()
    }

    public func allBrowserColumns() async throws -> Anki_Search_BrowserColumns {
        throw unavailableError()
    }

    public func browserRowForId(id _: Int64) async throws -> Anki_Search_BrowserRow {
        throw unavailableError()
    }

    public func removeNotes(noteIds _: [Int64], cardIds _: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    // Stable bridge signature; wrapping this in a parameter object would not simplify the call sites.
    // swiftlint:disable:next function_parameter_count
    public func findAndReplace(
        nids _: [Int64],
        search _: String,
        replacement _: String,
        regex _: Bool,
        matchCase _: Bool,
        fieldName _: String
    ) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func setActiveBrowserColumns(columns _: [String]) async throws {
        throw unavailableError()
    }

    public func setDueDate(cardIds _: [Int64],
                    days _: String) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func scheduleCardsAsNew(
        cardIds _: [Int64],
        log _: Bool,
        restorePosition _: Bool,
        resetCounts _: Bool
    ) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func addNoteTags(noteIds _: [Int64], tags _: String) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func removeNoteTags(noteIds _: [Int64], tags _: String) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func getGraphs(search _: String,
                   days _: UInt32) async throws -> Anki_Stats_GraphsResponse {
        throw unavailableError()
    }

    public func getNotetypeNames() async throws -> Anki_Notetypes_NotetypeNames {
        throw unavailableError()
    }

    public func getNotetype(id _: Int64) async throws -> Anki_Notetypes_Notetype {
        throw unavailableError()
    }

    public func allTags() async throws -> Anki_Generic_StringList {
        throw unavailableError()
    }

    public func getCard(id _: Int64) async throws -> Anki_Cards_Card {
        throw unavailableError()
    }

    public func updateNotes(notes _: [Anki_Notes_Note]) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func getUndoStatus() async throws -> Anki_Collection_UndoStatus {
        throw unavailableError()
    }

    public func undo() async throws -> Anki_Collection_OpChangesAfterUndo {
        throw unavailableError()
    }

    public func redo() async throws -> Anki_Collection_OpChangesAfterUndo {
        throw unavailableError()
    }

    public func extractAvTags(text _: String, questionSide _: Bool) async throws -> Anki_CardRendering_ExtractAvTagsResponse {
        throw unavailableError()
    }

    public func clozeNumbersInNote(note _: Anki_Notes_Note) async throws -> Anki_Notes_ClozeNumbersInNoteResponse {
        throw unavailableError()
    }

    public func noteFieldsCheck(note _: Anki_Notes_Note) async throws -> Anki_Notes_NoteFieldsCheckResponse {
        throw unavailableError()
    }

    public func syncLogin(username _: String,
                   password _: String) async throws -> Anki_Sync_SyncAuth {
        throw unavailableError()
    }

    public func syncStatus(auth _: Anki_Sync_SyncAuth) async throws -> Anki_Sync_SyncStatusResponse {
        throw unavailableError()
    }

    public func syncCollection(auth _: Anki_Sync_SyncAuth,
                        syncMedia _: Bool) async throws -> Anki_Sync_SyncCollectionResponse {
        throw unavailableError()
    }

    public func fullUploadOrDownload(auth _: Anki_Sync_SyncAuth, upload _: Bool, serverUsn _: Int32?) async throws {
        throw unavailableError()
    }

    public func syncMedia(auth _: Anki_Sync_SyncAuth) async throws {
        throw unavailableError()
    }

    public func newDeck() async throws -> Anki_Decks_Deck {
        throw unavailableError()
    }

    public func addDeck(deck _: Anki_Decks_Deck) async throws -> Anki_Collection_OpChangesWithId {
        throw unavailableError()
    }

    public func getDeck(id _: Int64) async throws -> Anki_Decks_Deck {
        throw unavailableError()
    }

    public func updateDeck(deck _: Anki_Decks_Deck) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func removeDecks(ids _: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func renameDeck(deckId _: Int64,
                    newName _: String) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func getDeckConfigsForUpdate(deckId _: Int64) async throws -> Anki_DeckConfig_DeckConfigsForUpdate {
        throw unavailableError()
    }

    public func updateDeckConfigs(request _: Anki_DeckConfig_UpdateDeckConfigsRequest) async throws
        -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func addMediaFile(desiredName _: String, data _: Data) async throws -> String {
        throw unavailableError()
    }

    public func buryOrSuspendCards(
        cardIds _: [Int64],
        noteIds _: [Int64],
        mode _: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode
    ) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func setFlag(cardIds _: [Int64], flag _: UInt32) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func importAnkiPackage(path _: String, options _: Anki_ImportExport_ImportAnkiPackageOptions) async throws
        -> Anki_ImportExport_ImportResponse {
        throw unavailableError()
    }

    public func exportAnkiPackage(
        outPath _: String,
        options _: Anki_ImportExport_ExportAnkiPackageOptions,
        limit _: Anki_ImportExport_ExportLimit
    ) async throws -> UInt32 {
        throw unavailableError()
    }

    public func getCsvMetadata(
        path _: String,
        delimiter _: Anki_ImportExport_CsvMetadata.Delimiter?,
        notetypeId _: Int64?,
        deckId _: Int64?,
        isHtml _: Bool?
    ) async throws -> Anki_ImportExport_CsvMetadata {
        throw unavailableError()
    }

    public func importCsv(path _: String, metadata _: Anki_ImportExport_CsvMetadata) async throws
        -> Anki_ImportExport_ImportResponse {
        throw unavailableError()
    }

    public func checkMedia() async throws -> Anki_Media_CheckMediaResponse {
        throw unavailableError()
    }

    public func trashMediaFiles(filenames _: [String]) async throws {
        throw unavailableError()
    }

    public func emptyTrash() async throws {
        throw unavailableError()
    }

    public func restoreTrash() async throws {
        throw unavailableError()
    }

    public func cardsOfNote(noteId _: Int64) async throws -> [Int64] {
        throw unavailableError()
    }

    public func addNotetype(notetype _: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChangesWithId {
        throw unavailableError()
    }

    public func updateNotetype(notetype _: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func removeNotetype(id _: Int64) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func getNotetypeNamesAndCounts() async throws -> Anki_Notetypes_NotetypeUseCounts {
        throw unavailableError()
    }

    public func getImageForOcclusion(path _: String) async throws -> Anki_ImageOcclusion_GetImageForOcclusionResponse {
        throw unavailableError()
    }

    public func getImageOcclusionNote(noteId _: Int64) async throws -> Anki_ImageOcclusion_GetImageOcclusionNoteResponse {
        throw unavailableError()
    }

    public func addImageOcclusionNote(request _: Anki_ImageOcclusion_AddImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func updateImageOcclusionNote(request _: Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func customStudy(request _: Anki_Scheduler_CustomStudyRequest) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func customStudyDefaults(deckId _: Int64) async throws -> Anki_Scheduler_CustomStudyDefaultsResponse {
        throw unavailableError()
    }

    public func emptyFilteredDeck(deckId _: Int64) async throws -> Anki_Collection_OpChanges {
        throw unavailableError()
    }

    public func rebuildFilteredDeck(deckId _: Int64) async throws -> Anki_Collection_OpChangesWithCount {
        throw unavailableError()
    }

    public func createBackup(backupFolder _: String, force _: Bool, waitForCompletion _: Bool) async throws -> Bool {
        throw unavailableError()
    }

    public func awaitBackupCompletion() async throws -> Bool {
        throw unavailableError()
    }

    public func setBrowserTableNotesMode(_: Bool) async throws {
        throw unavailableError()
    }

    public func getPreferences() async throws -> Anki_Config_Preferences {
        throw unavailableError()
    }

    public func setPreferences(prefs _: Anki_Config_Preferences) async throws {
        throw unavailableError()
    }

    public func compareAnswer(expected _: String, provided _: String, combining _: Bool) async throws -> String {
        throw unavailableError()
    }

    public func getCardStats(cardId _: Int64) async throws -> Anki_Stats_CardStatsResponse {
        throw unavailableError()
    }
}

public actor UnavailableAnkiService: AnkiServiceProtocol {
    public init() {}
}
