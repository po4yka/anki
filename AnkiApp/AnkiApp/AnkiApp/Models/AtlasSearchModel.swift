import Foundation
import Observation

@Observable
@MainActor
final class AtlasSearchModel {
    var query: String = ""
    var searchMode: SearchMode = .hybrid
    var results: [SearchResultItem] = []
    var isSearching: Bool = false
    var error: String? = nil

    private let atlas: AtlasService

    init(atlas: AtlasService) {
        self.atlas = atlas
    }

    func search() async {
        guard !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        error = nil
        let request = SearchRequest(query: query, searchMode: searchMode)
        do {
            let response: SearchResponse = try await atlas.command(method: "search", request: request)
            results = response.results
        } catch {
            self.error = error.localizedDescription
            results = []
        }
        isSearching = false
    }
}
