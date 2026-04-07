import Foundation
import Observation

struct DeckItem {
    let id: Int64
    let name: String
}

@Observable
@MainActor
final class NoteEditorModel {
    var note: Anki_Notes_Note? = nil
    var notetypeNames: Anki_Notetypes_NotetypeNames? = nil
    var isSaving: Bool = false
    var isLoading: Bool = false
    var error: AnkiError? = nil
    var editingNoteId: Int64? = nil
    var selectedDeckId: Int64 = 0
    var deckTree: Anki_Decks_DeckTreeNode? = nil
    var selectedNotetypeId: Int64 = 0
    var currentNotetype: Anki_Notetypes_Notetype? = nil

    var availableNotetypes: [Anki_Notetypes_NotetypeNameId] {
        notetypeNames?.entries ?? []
    }

    var fields: [String] {
        get { note?.fields ?? [] }
        set { note?.fields = newValue }
    }

    var fieldNames: [String] {
        currentNotetype?.fields.map { $0.name } ?? []
    }

    var availableDecks: [DeckItem] {
        guard let tree = deckTree else { return [] }
        var result: [DeckItem] = []
        func collect(_ node: Anki_Decks_DeckTreeNode) {
            result.append(DeckItem(id: node.deckID, name: node.name))
            for child in node.children { collect(child) }
        }
        for child in tree.children { collect(child) }
        return result
    }

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadNote(id: Int64) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedNote = try await service.getNote(id: id)
            note = loadedNote
            editingNoteId = id
            selectedNotetypeId = loadedNote.notetypeID
            await loadNotetype()
            // Find the deck from the first card of this note
            let cards = try await service.searchCards(
                search: "nid:\(id)",
                order: Anki_Search_SortOrder()
            )
            if let firstCardId = cards.ids.first {
                let card = try await service.getCard(id: firstCardId)
                selectedDeckId = card.deckID
            }
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func load() async {
        await loadNotetypeNames()
        await loadDecks()
    }

    func loadNotetype() async {
        guard selectedNotetypeId != 0 else { return }
        do {
            currentNotetype = try await service.getNotetype(id: selectedNotetypeId)
        } catch {}
    }

    func save() async {
        guard var noteToSave = note else { return }
        noteToSave.notetypeID = selectedNotetypeId
        noteToSave.tags = tags
        if editingNoteId != nil {
            await updateNote(note: noteToSave)
        } else {
            await addNote(note: noteToSave, deckId: selectedDeckId)
        }
    }

    func loadDecks() async {
        do {
            let now = Int64(Date().timeIntervalSince1970)
            deckTree = try await service.getDeckTree(now: now)
        } catch {}
    }

    func loadNotetypeNames() async {
        do {
            notetypeNames = try await service.getNotetypeNames()
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    var tags: [String] {
        get { note?.tags ?? [] }
        set { note?.tags = newValue }
    }

    func addTag(_ tag: String) {
        if note != nil, !tags.contains(tag) {
            note?.tags.append(tag)
        }
    }

    func removeTag(_ tag: String) {
        note?.tags.removeAll { $0 == tag }
    }

    func addNote(note: Anki_Notes_Note, deckId: Int64) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.addNote(note: note, deckId: deckId)
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func updateNote(note: Anki_Notes_Note) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.updateNotes(notes: [note])
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }
}
