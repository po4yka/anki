import Foundation
import Observation

@Observable
@MainActor
final class CardGeneratorModel {
    var sourceText: String = ""
    var topic: String = ""
    var preview: GeneratePreview?
    var isGenerating: Bool = false
    var isSaving: Bool = false
    var savedCount: Int?
    var error: String?

    private let atlas: any AtlasServiceProtocol

    init(atlas: any AtlasServiceProtocol) {
        self.atlas = atlas
    }

    func generatePreview() async {
        guard !sourceText.isEmpty else { return }
        isGenerating = true
        error = nil
        savedCount = nil
        do {
            let request = GeneratePreviewRequest(
                sourceText: sourceText,
                topic: topic.isEmpty ? nil : topic
            )
            let result = try await atlas.generatePreviewFromText(request)
            preview = result
        } catch {
            self.error = error.localizedDescription
            preview = nil
        }
        isGenerating = false
    }

    func saveCards(service: AnkiService) async {
        guard let cards = preview?.cards, !cards.isEmpty else { return }
        isSaving = true
        error = nil
        savedCount = nil
        do {
            // Fetch notetype names to find the Basic notetype ID
            let notetypeNames = try await service.getNotetypeNames()
            guard let basicEntry = notetypeNames.entries.first(where: { $0.name == "Basic" })
                ?? notetypeNames.entries.first
            else {
                error = "No notetypes available."
                isSaving = false
                return
            }
            let notetypeId = basicEntry.id
            // Fetch the full notetype to get field order
            let notetype = try await service.getNotetype(id: notetypeId)

            var count = 0
            for card in cards {
                var note = Anki_Notes_Note()
                note.notetypeID = notetypeId
                // Map front to first field, back to second field (Basic notetype layout)
                if notetype.fields.count >= 2 {
                    note.fields = [card.front, card.back]
                } else if notetype.fields.count == 1 {
                    note.fields = [card.front]
                } else {
                    note.fields = [card.front, card.back]
                }
                // Use deck ID 1 (Default deck)
                _ = try await service.addNote(note: note, deckId: 1)
                count += 1
            }
            savedCount = count
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
