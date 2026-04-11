// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
    public func renderExistingCard(cardId: Int64) async throws -> Anki_CardRendering_RenderCardResponse {
        var req = Anki_CardRendering_RenderExistingCardRequest()
        req.cardID = cardId
        return try backend.command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.renderExistingCard,
            input: req
        )
    }

    public func extractAvTags(text: String, questionSide: Bool) async throws -> Anki_CardRendering_ExtractAvTagsResponse {
        var req = Anki_CardRendering_ExtractAvTagsRequest()
        req.text = text
        req.questionSide = questionSide
        return try backend.command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.extractAvTags,
            input: req
        )
    }

    public func compareAnswer(expected: String, provided: String, combining: Bool) async throws -> String {
        var req = Anki_CardRendering_CompareAnswerRequest()
        req.expected = expected
        req.provided = provided
        req.combining = combining
        let response: Anki_Generic_String = try backend.command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.compareAnswer,
            input: req
        )
        return response.val
    }
}
