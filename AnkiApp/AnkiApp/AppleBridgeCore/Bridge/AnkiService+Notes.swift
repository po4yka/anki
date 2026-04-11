// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
import Foundation

extension AnkiService {
    public func newNote(notetypeId: Int64) async throws -> Anki_Notes_Note {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = notetypeId
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.newNote,
            input: req
        )
    }

    public func defaultsForAdding(homeDeckOfCurrentReviewCard: Int64) async throws -> Anki_Notes_DeckAndNotetype {
        var req = Anki_Notes_DefaultsForAddingRequest()
        req.homeDeckOfCurrentReviewCard = homeDeckOfCurrentReviewCard
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.defaultsForAdding,
            input: req
        )
    }

    public func getNote(id: Int64) async throws -> Anki_Notes_Note {
        var req = Anki_Notes_NoteId()
        req.nid = id
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.getNote,
            input: req
        )
    }

    public func addNote(note: Anki_Notes_Note, deckId: Int64) async throws -> Anki_Notes_AddNoteResponse {
        var req = Anki_Notes_AddNoteRequest()
        req.note = note
        req.deckID = deckId
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.addNote,
            input: req
        )
    }

    public func updateNotes(notes: [Anki_Notes_Note]) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notes_UpdateNotesRequest()
        req.notes = notes
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.updateNotes,
            input: req
        )
    }

    public func removeNotes(noteIds: [Int64], cardIds: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Notes_RemoveNotesRequest()
        req.noteIds = noteIds
        req.cardIds = cardIds
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.removeNotes,
            input: req
        )
    }

    public func clozeNumbersInNote(note: Anki_Notes_Note) async throws -> Anki_Notes_ClozeNumbersInNoteResponse {
        try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.clozeNumbersInNote,
            input: note
        )
    }

    public func noteFieldsCheck(note: Anki_Notes_Note) async throws -> Anki_Notes_NoteFieldsCheckResponse {
        try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.noteFieldsCheck,
            input: note
        )
    }

    public func cardsOfNote(noteId: Int64) async throws -> [Int64] {
        var req = Anki_Notes_NoteId()
        req.nid = noteId
        let response: Anki_Cards_CardIds = try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.cardsOfNote,
            input: req
        )
        return response.cids
    }
}
#endif
