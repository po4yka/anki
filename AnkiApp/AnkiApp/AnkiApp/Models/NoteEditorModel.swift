import AppleBridgeCore
import AppleSharedUI
import Foundation
import Observation

struct DeckItem {
    let id: Int64
    let name: String
}

@Observable
@MainActor
final class NoteEditorModel {
    var note: Anki_Notes_Note?
    var notetypeNames: Anki_Notetypes_NotetypeNames?
    var isSaving: Bool = false
    var isLoading: Bool = false
    var error: AnkiError?
    var editingNoteId: Int64?
    var selectedDeckId: Int64 = 0
    var deckTree: Anki_Decks_DeckTreeNode?
    var selectedNotetypeId: Int64 = 0
    var currentNotetype: Anki_Notetypes_Notetype?
    var isClozeNotetype: Bool = false

    var availableNotetypes: [Anki_Notetypes_NotetypeNameId] {
        notetypeNames?.entries ?? []
    }

    var fields: [String] {
        get { note?.fields ?? [] }
        set { note?.fields = newValue }
    }

    var fieldNames: [String] {
        currentNotetype?.fields.map(\.name) ?? []
    }

    var fieldRequirements: FieldRequirements? {
        guard let notetype = currentNotetype, let note else { return nil }
        guard notetype.config.kind != .cloze else { return nil }
        return FieldRequirementsHelper.analyze(notetype: notetype, fieldValues: note.fields)
    }

    func isFieldRequired(_ index: Int) -> Bool {
        fieldRequirements?.requiredFieldIndexes.contains(index) ?? false
    }

    var predictedCardCount: Int {
        fieldRequirements?.cardCount ?? 0
    }

    var availableDecks: [DeckItem] {
        guard let tree = deckTree else { return [] }
        var result: [DeckItem] = []
        func collect(_ node: Anki_Decks_DeckTreeNode) {
            result.append(DeckItem(id: node.deckID, name: node.name))
            for child in node.children {
                collect(child)
            }
        }
        for child in tree.children {
            collect(child)
        }
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
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func load() async {
        await loadNotetypeNames()
        await loadDecks()
        if editingNoteId == nil {
            await prepareNewNote()
        }
    }

    func loadNotetype() async {
        guard selectedNotetypeId != 0 else { return }
        do {
            let notetype = try await service.getNotetype(id: selectedNotetypeId)
            currentNotetype = notetype
            isClozeNotetype = notetype.config.kind == .cloze
            if editingNoteId == nil {
                note = try await service.newNote(notetypeId: selectedNotetypeId)
                note?.notetypeID = selectedNotetypeId
            }
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
        } catch let ankiError as AnkiError {
            error = ankiError
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
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func updateNote(note: Anki_Notes_Note) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.updateNotes(notes: [note])
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func nextClozeNumber() async -> Int {
        guard let note else { return 1 }
        do {
            let response = try await service.clozeNumbersInNote(note: note)
            let existing = response.numbers.map { Int($0) }
            return ClozeHelper.nextClozeNumber(existing: existing)
        } catch {
            return 1
        }
    }

    func validateFields() async -> Anki_Notes_NoteFieldsCheckResponse? {
        guard let note else { return nil }
        do {
            return try await service.noteFieldsCheck(note: note)
        } catch {
            return nil
        }
    }

    func attachImage(desiredName: String, data: Data) async -> String? {
        do {
            return try await service.addMediaFile(desiredName: desiredName, data: data)
        } catch let ankiError as AnkiError {
            error = ankiError
            return nil
        } catch {
            return nil
        }
    }

    private func prepareNewNote() async {
        do {
            let defaults = try await service.defaultsForAdding(homeDeckOfCurrentReviewCard: 0)
            selectedDeckId = defaults.deckID
            selectedNotetypeId = defaults.notetypeID
            await loadNotetype()
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }
}
