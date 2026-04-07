import Foundation

protocol AnkiServiceProtocol: Sendable {
    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws
    func closeCollection(downgrade: Bool) async throws
    func getDeckTree(now: Int64) async throws -> Anki_Decks_DeckTreeNode
    func getQueuedCards(fetchLimit: UInt32) async throws -> Anki_Scheduler_QueuedCards
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
    func browserRowForId(id: Int64) async throws -> Anki_Search_BrowserRow
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
}
