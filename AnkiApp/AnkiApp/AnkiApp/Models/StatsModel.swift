import Foundation
import Observation

@Observable
@MainActor
final class StatsModel {
    var graphs: Anki_Stats_GraphsResponse? = nil
    var isLoading: Bool = false
    var error: AnkiError? = nil

    var search: String = ""
    var days: UInt32 = 365

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            graphs = try await service.getGraphs(search: search, days: days)
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }
}
