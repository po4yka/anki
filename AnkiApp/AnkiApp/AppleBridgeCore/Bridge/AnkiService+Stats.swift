// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
    public func getGraphs(search: String, days: UInt32) async throws -> Anki_Stats_GraphsResponse {
        var req = Anki_Stats_GraphsRequest()
        req.search = search
        req.days = days
        return try backend.command(
            service: ServiceIndex.stats,
            method: StatsMethod.graphs,
            input: req
        )
    }

    public func getCardStats(cardId: Int64) async throws -> Anki_Stats_CardStatsResponse {
        var req = Anki_Cards_CardId()
        req.cid = cardId
        return try backend.command(
            service: ServiceIndex.stats,
            method: StatsMethod.cardStats,
            input: req
        )
    }
}
