import Foundation
import Observation

@Observable
@MainActor
final class ReviewerModel {
    var queuedCards: Anki_Scheduler_QueuedCards?
    var currentCardHTML: Anki_CardRendering_RenderCardResponse?
    var isLoading: Bool = false
    var error: AnkiError?

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
                currentCardHTML = try await service.renderExistingCard(cardId: cardId, browser: false)
            }
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
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
        } catch let e as AnkiError {
            error = e
        } catch {}
    }
}
