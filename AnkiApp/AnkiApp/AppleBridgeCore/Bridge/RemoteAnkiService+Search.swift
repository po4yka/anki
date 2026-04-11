import Foundation

public extension RemoteAnkiService {
    func searchCards(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        var req = Anki_Search_SearchRequest()
        req.search = search
        req.order = order
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.searchCards,
            input: req
        )
    }

    func searchNotes(search: String, order: Anki_Search_SortOrder) async throws -> Anki_Search_SearchResponse {
        var req = Anki_Search_SearchRequest()
        req.search = search
        req.order = order
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.searchNotes,
            input: req
        )
    }

    func allBrowserColumns() async throws -> Anki_Search_BrowserColumns {
        try await command(
            service: ServiceIndex.search,
            method: SearchMethod.allBrowserColumns,
            input: Anki_Generic_Empty()
        )
    }

    func browserRowForId(id: Int64) async throws -> Anki_Search_BrowserRow {
        var req = Anki_Generic_Int64()
        req.val = id
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.browserRowForId,
            input: req
        )
    }

    // Stable bridge signature; wrapping this in a parameter object would not simplify the call sites.
    // swiftlint:disable:next function_parameter_count
    func findAndReplace(
        nids: [Int64],
        search: String,
        replacement: String,
        regex: Bool,
        matchCase: Bool,
        fieldName: String
    ) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Search_FindAndReplaceRequest()
        req.nids = nids
        req.search = search
        req.replacement = replacement
        req.regex = regex
        req.matchCase = matchCase
        req.fieldName = fieldName
        return try await command(
            service: ServiceIndex.search,
            method: SearchMethod.findAndReplace,
            input: req
        )
    }

    func setActiveBrowserColumns(columns: [String]) async throws {
        var req = Anki_Generic_StringList()
        req.vals = columns
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.search,
            method: SearchMethod.setActiveBrowserColumns,
            input: req
        )
    }
}
