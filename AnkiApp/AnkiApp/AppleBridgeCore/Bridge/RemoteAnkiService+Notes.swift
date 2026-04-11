import Foundation

public extension RemoteAnkiService {
    func newNote(notetypeId: Int64) async throws -> Anki_Notes_Note {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = notetypeId
        return try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.newNote,
            input: req
        )
    }

    func defaultsForAdding(homeDeckOfCurrentReviewCard: Int64) async throws -> Anki_Notes_DeckAndNotetype {
        var req = Anki_Notes_DefaultsForAddingRequest()
        req.homeDeckOfCurrentReviewCard = homeDeckOfCurrentReviewCard
        return try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.defaultsForAdding,
            input: req
        )
    }

    func getNote(id: Int64) async throws -> Anki_Notes_Note {
        var req = Anki_Notes_NoteId()
        req.nid = id
        return try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.getNote,
            input: req
        )
    }

    func addNote(note: Anki_Notes_Note, deckId: Int64) async throws -> Anki_Notes_AddNoteResponse {
        var req = Anki_Notes_AddNoteRequest()
        req.note = note
        req.deckID = deckId
        return try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.addNote,
            input: req
        )
    }

    func updateNotes(notes: [Anki_Notes_Note]) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notes_UpdateNotesRequest()
        req.notes = notes
        return try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.updateNotes,
            input: req
        )
    }

    func clozeNumbersInNote(note: Anki_Notes_Note) async throws -> Anki_Notes_ClozeNumbersInNoteResponse {
        try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.clozeNumbersInNote,
            input: note
        )
    }

    func noteFieldsCheck(note: Anki_Notes_Note) async throws -> Anki_Notes_NoteFieldsCheckResponse {
        try await command(
            service: ServiceIndex.notes,
            method: NotesMethod.noteFieldsCheck,
            input: note
        )
    }
}
