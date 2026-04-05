import Foundation
import Observation

@Observable
@MainActor
final class SearchModel {
    var query: String = ""
    var cardIds: [Int64] = []
    var rows: [Int64: Anki_Search_BrowserRow] = [:]
    var isSearching: Bool = false
    var error: AnkiError? = nil

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func search() async {
        guard !query.isEmpty else {
            cardIds = []
            rows = [:]
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await service.searchCards(
                search: query,
                order: Anki_Search_SortOrder()
            )
            cardIds = response.ids
            rows = [:]
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func loadRow(id: Int64) async {
        do {
            let row = try await service.browserRowForId(id: id)
            rows[id] = row
        } catch {}
    }
}
