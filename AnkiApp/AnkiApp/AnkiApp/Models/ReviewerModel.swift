import Foundation
import Observation

@Observable
@MainActor
final class ReviewerModel {
    var queuedCards: Anki_Scheduler_QueuedCards? = nil
    var currentCardHTML: Anki_CardRendering_RenderCardResponse? = nil
    var currentAvTags: [Anki_CardRendering_AVTag] = []
    var undoLabel: String? = nil
    var isLoading: Bool = false
    var error: AnkiError? = nil

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadQueue() async {
        isLoading = true
        defer { isLoading = false }
        do {
            queuedCards = try await service.getQueuedCards(fetchLimit: 1)
            if let cardId = queuedCards?.cards.first?.card.id {
                currentCardHTML = try await service.renderExistingCard(cardId: cardId)
                await extractAvTags()
            }
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    private func extractAvTags() async {
        guard let rendered = currentCardHTML else {
            currentAvTags = []
            return
        }
        let text = rendered.answerNodes.map { node -> String in
            if !node.text.isEmpty { return node.text }
            return node.replacement.currentText
        }.joined()
        do {
            let response = try await service.extractAvTags(text: text, questionSide: false)
            currentAvTags = response.avTags
        } catch {
            currentAvTags = []
        }
    }

    func answerCard(
        cardId: Int64,
        rating: Anki_Scheduler_CardAnswer.Rating,
        currentState: Anki_Scheduler_SchedulingState,
        newState: Anki_Scheduler_SchedulingState
    ) async {
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            _ = try await service.answerCard(
                cardId: cardId,
                rating: rating,
                currentState: currentState,
                newState: newState,
                answeredAtMillis: now,
                millisecondsTaken: 0
            )
            await loadQueue()
            await refreshUndoStatus()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func undoLastAnswer() async {
        do {
            _ = try await service.undo()
            await loadQueue()
            await refreshUndoStatus()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    var currentFlag: UInt32 {
        queuedCards?.cards.first?.card.flags ?? 0
    }

    func buryCard() async {
        guard let cardId = queuedCards?.cards.first?.card.id else { return }
        do {
            _ = try await service.buryOrSuspendCards(cardIds: [cardId], noteIds: [], mode: .buryUser)
            await loadQueue()
            await refreshUndoStatus()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func buryNote() async {
        guard let noteId = queuedCards?.cards.first?.card.noteID else { return }
        do {
            _ = try await service.buryOrSuspendCards(cardIds: [], noteIds: [noteId], mode: .buryUser)
            await loadQueue()
            await refreshUndoStatus()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func suspendCard() async {
        guard let cardId = queuedCards?.cards.first?.card.id else { return }
        do {
            _ = try await service.buryOrSuspendCards(cardIds: [cardId], noteIds: [], mode: .suspend)
            await loadQueue()
            await refreshUndoStatus()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func flagCard(flag: UInt32) async {
        guard let cardId = queuedCards?.cards.first?.card.id else { return }
        do {
            _ = try await service.setFlag(cardIds: [cardId], flag: flag)
            await loadQueue()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    private func refreshUndoStatus() async {
        do {
            let status = try await service.getUndoStatus()
            undoLabel = status.undo.isEmpty ? nil : status.undo
        } catch {
            undoLabel = nil
        }
    }
}
