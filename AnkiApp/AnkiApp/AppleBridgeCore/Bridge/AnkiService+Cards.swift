// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
    public func getCard(id: Int64) async throws -> Anki_Cards_Card {
        var req = Anki_Cards_CardId()
        req.cid = id
        return try backend.command(
            service: ServiceIndex.cards,
            method: CardsMethod.getCard,
            input: req
        )
    }

    public func setFlag(cardIds: [Int64], flag: UInt32) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Cards_SetFlagRequest()
        req.cardIds = cardIds
        req.flag = flag
        return try backend.command(
            service: ServiceIndex.cards,
            method: CardsMethod.setFlag,
            input: req
        )
    }
}
