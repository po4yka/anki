// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

public extension AnkiService {
    func getQueuedCards(fetchLimit: UInt32) async throws -> Anki_Scheduler_QueuedCards {
        var req = Anki_Scheduler_GetQueuedCardsRequest()
        req.fetchLimit = fetchLimit
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.getQueuedCards,
            input: req
        )
    }

    // swiftlint:disable:next function_parameter_count
    func answerCard(
        cardId: Int64,
        rating: Anki_Scheduler_CardAnswer.Rating,
        currentState: Anki_Scheduler_SchedulingState,
        newState: Anki_Scheduler_SchedulingState,
        answeredAtMillis: Int64,
        millisecondsTaken: UInt32
    ) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_CardAnswer()
        req.cardID = cardId
        req.rating = rating
        req.currentState = currentState
        req.newState = newState
        req.answeredAtMillis = answeredAtMillis
        req.millisecondsTaken = millisecondsTaken
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.answerCard,
            input: req
        )
    }

    func setDueDate(cardIds: [Int64], days: String) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_SetDueDateRequest()
        req.cardIds = cardIds
        req.days = days
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.setDueDate,
            input: req
        )
    }

    func scheduleCardsAsNew(cardIds: [Int64], log: Bool, restorePosition: Bool,
                            resetCounts: Bool) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Scheduler_ScheduleCardsAsNewRequest()
        req.cardIds = cardIds
        req.log = log
        req.restorePosition = restorePosition
        req.resetCounts = resetCounts
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.scheduleCardsAsNew,
            input: req
        )
    }

    func buryOrSuspendCards(
        cardIds: [Int64],
        noteIds: [Int64],
        mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode
    ) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
        req.cardIds = cardIds
        req.noteIds = noteIds
        req.mode = mode
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.buryOrSuspendCards,
            input: req
        )
    }

    func customStudy(request: Anki_Scheduler_CustomStudyRequest) async throws -> Anki_Collection_OpChanges {
        try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.customStudy,
            input: request
        )
    }

    func customStudyDefaults(deckId: Int64) async throws -> Anki_Scheduler_CustomStudyDefaultsResponse {
        var req = Anki_Scheduler_CustomStudyDefaultsRequest()
        req.deckID = deckId
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.customStudyDefaults,
            input: req
        )
    }

    func emptyFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.emptyFilteredDeck,
            input: req
        )
    }

    func rebuildFilteredDeck(deckId: Int64) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Decks_DeckId()
        req.did = deckId
        return try backend.command(
            service: ServiceIndex.scheduler,
            method: SchedulerMethod.rebuildFilteredDeck,
            input: req
        )
    }
}
