import Foundation
import Observation

enum BrowserSearchMode: String, CaseIterable {
    case cards = "Cards"
    case notes = "Notes"
}

struct BrowserRowItem: Identifiable {
    let id: Int64
    let row: Anki_Search_BrowserRow
    let questionPreview: String
    let deckName: String
    let due: String

    init(id: Int64, row: Anki_Search_BrowserRow) {
        self.id = id
        self.row = row
        self.questionPreview = row.cells.first?.text ?? ""
        self.deckName = row.cells.count > 1 ? row.cells[1].text : ""
        self.due = row.cells.count > 2 ? row.cells[2].text : ""
    }
}

@Observable
@MainActor
final class SearchModel {
    var query: String = ""
    var cardIds: [Int64] = []
    var rows: [Int64: Anki_Search_BrowserRow] = [:]
    var isSearching: Bool = false
    var error: AnkiError? = nil

    var sortColumn: String = ""
    var sortReverse: Bool = false
    var selectedCardIds: Set<Int64> = []
    var searchMode: BrowserSearchMode = .cards

    var allColumns: [Anki_Search_BrowserColumns.Column] = []
    var visibleColumnKeys: [String] = ["question", "deck", "due"]

    var results: [BrowserRowItem] {
        cardIds.compactMap { id in
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
        guard !query.isEmpty else {
            cardIds = []
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
            let response: Anki_Search_SearchResponse
            switch searchMode {
            case .cards:
                response = try await service.searchCards(search: query, order: order)
            case .notes:
                response = try await service.searchNotes(search: query, order: order)
            }
            cardIds = response.ids
            rows = [:]
            error = nil
            for id in cardIds {
                await loadRow(id: id)
            }
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
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) else {
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
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.removeNotes(noteIds: [], cardIds: ids)
            selectedCardIds.removeAll()
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func setDueDateForSelected(days: String) async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.setDueDate(cardIds: ids, days: days)
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func addTagsToSelected(tags: String) async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.addNoteTags(noteIds: ids, tags: tags)
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func removeTagsFromSelected(tags: String) async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.removeNoteTags(noteIds: ids, tags: tags)
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func suspendSelected() async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.buryOrSuspendCards(cardIds: ids, noteIds: [], mode: .suspend)
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func burySelected() async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.buryOrSuspendCards(cardIds: ids, noteIds: [], mode: .buryUser)
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func forgetSelected() async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.scheduleCardsAsNew(cardIds: ids, log: true, restorePosition: false, resetCounts: true)
            await search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func findAndReplace(search: String, replacement: String, regex: Bool, matchCase: Bool, fieldName: String) async {
        guard !selectedCardIds.isEmpty else { return }
        do {
            let ids = Array(selectedCardIds)
            let _ = try await service.findAndReplace(
                nids: ids, search: search, replacement: replacement,
                regex: regex, matchCase: matchCase, fieldName: fieldName
            )
            await self.search()
        } catch let e as AnkiError {
            error = e
        } catch {}
    }
}
