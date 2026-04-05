import Foundation
import Observation

@Observable
@MainActor
final class NoteEditorModel {
    var note: Anki_Notes_Note? = nil
    var notetypeNames: Anki_Notetypes_NotetypeNames? = nil
    var isSaving: Bool = false
    var isLoading: Bool = false
    var error: AnkiError? = nil

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadNote(id: Int64) async {
        isLoading = true
        defer { isLoading = false }
        do {
            note = try await service.getNote(id: id)
            error = nil
        } catch let e as AnkiError {
            error = e
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
}
