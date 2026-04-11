import Foundation
import Observation

enum BrowserSearchMode: String, CaseIterable {
    case cards = "Cards"
    case notes = "Notes"
}

struct BrowserRowItem: Identifiable {
    let id: Int64
    let cells: [String]
    let color: Anki_Search_BrowserRow.Color

    init(id: Int64, row: Anki_Search_BrowserRow) {
        self.id = id
        cells = row.cells.map(\.text)
        color = row.color
    }

    func cell(at index: Int) -> String {
        index < cells.count ? cells[index] : ""
    }
}

@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class SearchModel {
    var query: String = ""
    var resultIds: [Int64] = []
    var rows: [Int64: Anki_Search_BrowserRow] = [:]
    var isSearching: Bool = false
    var error: AnkiError?

    var sortColumn: String = ""
    var sortReverse: Bool = false
    var selectedResultIds: Set<Int64> = []
    var searchMode: BrowserSearchMode = .cards

    var allColumns: [Anki_Search_BrowserColumns.Column] = []
    var visibleColumnKeys: [String] = ["question", "deck", "due"]

    var visibleColumns: [Anki_Search_BrowserColumns.Column] {
        visibleColumnKeys.compactMap { key in
            allColumns.first { $0.key == key }
        }
    }

    var results: [BrowserRowItem] {
        resultIds.compactMap { id in
            guard let row = rows[id] else { return nil }
            return BrowserRowItem(id: id, row: row)
        }
    }

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadColumns() async {
        do {
            try await service.setBrowserTableNotesMode(searchMode == .notes)
            let response = try await service.allBrowserColumns()
            allColumns = response.columns
            let saved = UserDefaults.standard.stringArray(forKey: "browserVisibleColumns")
            if let saved, !saved.isEmpty {
                visibleColumnKeys = saved
            }
            try await service.setActiveBrowserColumns(columns: visibleColumnKeys)
        } catch {}
    }

    func toggleColumn(key: String) async {
        if visibleColumnKeys.contains(key) {
            visibleColumnKeys.removeAll { $0 == key }
        } else {
            visibleColumnKeys.append(key)
        }
        UserDefaults.standard.set(visibleColumnKeys, forKey: "browserVisibleColumns")
        do {
            try await service.setActiveBrowserColumns(columns: visibleColumnKeys)
            await search()
        } catch {}
    }

    func search() async {
        do {
            try await service.setBrowserTableNotesMode(searchMode == .notes)
        } catch let ankiError as AnkiError {
            error = ankiError
            return
        } catch let caughtError {
            error = .message("Failed to configure browser mode: \(caughtError.localizedDescription)")
            return
        }
        guard !query.isEmpty else {
            resultIds = []
            rows = [:]
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            var order = Anki_Search_SortOrder()
            if !sortColumn.isEmpty {
                var builtin = Anki_Search_SortOrder.Builtin()
                builtin.column = sortColumn
                builtin.reverse = sortReverse
                order.value = .builtin(builtin)
            }
            let response: Anki_Search_SearchResponse = switch searchMode {
                case .cards:
                    try await service.searchCards(search: query, order: order)
                case .notes:
                    try await service.searchNotes(search: query, order: order)
            }
            resultIds = response.ids
            rows = [:]
            error = nil
            for id in resultIds {
                await loadRow(id: id)
            }
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func loadRow(id: Int64) async {
        do {
            let row = try await service.browserRowForId(id: id)
            rows[id] = row
        } catch {}
    }

    func sort(by column: String) async {
        if sortColumn == column {
            sortReverse.toggle()
        } else {
            sortColumn = column
            sortReverse = false
        }
        await search()
    }

    // MARK: - Saved Searches

    struct SavedSearch: Codable, Identifiable {
        var id: UUID
        var name: String
        var query: String
    }

    var savedSearches: [SavedSearch] = []

    func loadSavedSearches() {
        guard let data = UserDefaults.standard.data(forKey: "savedSearches"),
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else {
            return
        }
        savedSearches = decoded
    }

    private func persistSavedSearches() {
        if let data = try? JSONEncoder().encode(savedSearches) {
            UserDefaults.standard.set(data, forKey: "savedSearches")
        }
    }

    func saveCurrentSearch(name: String) {
        guard !query.isEmpty else { return }
        let saved = SavedSearch(id: UUID(), name: name, query: query)
        savedSearches.append(saved)
        persistSavedSearches()
    }

    func deleteSavedSearch(id: UUID) {
        savedSearches.removeAll { $0.id == id }
        persistSavedSearches()
    }

    func renameSavedSearch(id: UUID, newName: String) {
        guard let idx = savedSearches.firstIndex(where: { $0.id == id }) else { return }
        savedSearches[idx].name = newName
        persistSavedSearches()
    }

    func applySavedSearch(_ saved: SavedSearch) async {
        query = saved.query
        await search()
    }

    // MARK: - Batch Operations

    func deleteSelected() async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            switch searchMode {
                case .cards:
                    let ids = Array(selectedResultIds)
                    _ = try await service.removeNotes(noteIds: [], cardIds: ids)
                case .notes:
                    let ids = Array(selectedResultIds)
                    _ = try await service.removeNotes(noteIds: ids, cardIds: [])
            }
            selectedResultIds.removeAll()
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func setDueDateForSelected(days: String) async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedCardIDs()
            _ = try await service.setDueDate(cardIds: ids, days: days)
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func addTagsToSelected(tags: String) async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedNoteIDs()
            _ = try await service.addNoteTags(noteIds: ids, tags: tags)
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func removeTagsFromSelected(tags: String) async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedNoteIDs()
            _ = try await service.removeNoteTags(noteIds: ids, tags: tags)
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func suspendSelected() async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedCardIDs()
            _ = try await service.buryOrSuspendCards(cardIds: ids, noteIds: [], mode: .suspend)
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func burySelected() async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedCardIDs()
            _ = try await service.buryOrSuspendCards(cardIds: ids, noteIds: [], mode: .buryUser)
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func forgetSelected() async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedCardIDs()
            _ = try await service.scheduleCardsAsNew(cardIds: ids, log: true, restorePosition: false, resetCounts: true)
            await search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func findAndReplace(search: String, replacement: String, regex: Bool, matchCase: Bool, fieldName: String) async {
        guard !selectedResultIds.isEmpty else { return }
        do {
            let ids = try await selectedNoteIDs()
            _ = try await service.findAndReplace(
                nids: ids, search: search, replacement: replacement,
                regex: regex, matchCase: matchCase, fieldName: fieldName
            )
            await self.search()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func noteID(for resultID: Int64) async -> Int64? {
        switch searchMode {
            case .notes:
                return resultID
            case .cards:
                do {
                    return try await service.getCard(id: resultID).noteID
                } catch {
                    return nil
                }
        }
    }

    private func selectedNoteIDs() async throws -> [Int64] {
        switch searchMode {
            case .notes:
                return Array(selectedResultIds)
            case .cards:
                var noteIDs = Set<Int64>()
                for cardID in selectedResultIds {
                    let card = try await service.getCard(id: cardID)
                    noteIDs.insert(card.noteID)
                }
                return Array(noteIDs)
        }
    }

    private func selectedCardIDs() async throws -> [Int64] {
        switch searchMode {
            case .cards:
                return Array(selectedResultIds)
            case .notes:
                var cardIDs: [Int64] = []
                for noteID in selectedResultIds {
                    try await cardIDs.append(contentsOf: service.cardsOfNote(noteId: noteID))
                }
                return cardIDs
        }
    }
}
