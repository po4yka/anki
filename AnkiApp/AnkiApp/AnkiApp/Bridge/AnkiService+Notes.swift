// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
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

    func updateNotes(notes: [Anki_Notes_Note]) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notes_UpdateNotesRequest()
        req.notes = notes
        return try backend.command(
            service: ServiceIndex.notes,
            method: NotesMethod.updateNotes,
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
}
