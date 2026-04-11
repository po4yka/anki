import Foundation
import Observation
import AppleBridgeCore
import AppleSharedUI

@Observable
@MainActor
final class CardGeneratorModel {
    var sourceText: String = ""
    var topic: String = ""
    var preview: GeneratePreview?
    var isGenerating: Bool = false
    var isSaving: Bool = false
    var savedCount: Int?
    var savedDeckName: String?
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

    func saveCards(service: any AnkiServiceProtocol) async {
        guard let cards = preview?.cards, !cards.isEmpty else { return }
        isSaving = true
        error = nil
        savedCount = nil
        savedDeckName = nil
        do {
            let defaults = try await service.defaultsForAdding(homeDeckOfCurrentReviewCard: 0)
            let deck = try await service.getDeck(id: defaults.deckID)
            let notetypeId = defaults.notetypeID

            var count = 0
            for card in cards {
                var note = try await service.newNote(notetypeId: notetypeId)
                note.notetypeID = notetypeId

                if note.fields.count >= 2 {
                    note.fields[0] = card.front
                    note.fields[1] = card.back
                } else if note.fields.count == 1 {
                    note.fields[0] = card.front
                } else {
                    note.fields = [card.front, card.back]
                }

                _ = try await service.addNote(note: note, deckId: defaults.deckID)
                count += 1
            }
            savedCount = count
            savedDeckName = deck.name
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
