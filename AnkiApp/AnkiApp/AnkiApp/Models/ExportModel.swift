import Foundation
import Observation
import AppleBridgeCore
import AppleSharedUI

@Observable
@MainActor
final class ExportModel {
    var isExporting = false
    var exportedCount: UInt32?
    var errorMessage: String?
    var options = ExportOptions()
    var exportScope: ExportScope = .wholeCollection
    var availableDecks: [(id: Int64, name: String)] = []
    var selectedDeckId: Int64 = 0

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
        Task { await load() }
    }

    func load() async {
        do {
            let tree = try await service.getDeckTree(now: 0)
            availableDecks = flattenDeckTree(tree)
            if let first = availableDecks.first {
                selectedDeckId = first.id
            }
        } catch {
            // Non-fatal: deck picker just stays empty
        }
    }

    private func flattenDeckTree(_ node: Anki_Decks_DeckTreeNode) -> [(id: Int64, name: String)] {
        var result: [(id: Int64, name: String)] = []
        if node.deckID != 0 {
            result.append((id: node.deckID, name: node.name))
        }
        for child in node.children {
            result.append(contentsOf: flattenDeckTree(child))
        }
        return result
    }

    struct ExportOptions {
        var withScheduling = true
        var withDeckConfigs = true
        var withMedia = true
        var legacy = false
    }

    enum ExportScope: Equatable {
        case wholeCollection
        case deck(id: Int64, name: String)
    }

    func exportPackage(outPath: String) async {
        isExporting = true
        exportedCount = nil
        errorMessage = nil

        var opts = Anki_ImportExport_ExportAnkiPackageOptions()
        opts.withScheduling = options.withScheduling
        opts.withDeckConfigs = options.withDeckConfigs
        opts.withMedia = options.withMedia
        opts.legacy = options.legacy

        var limit = Anki_ImportExport_ExportLimit()
        switch exportScope {
            case .wholeCollection:
                limit.wholeCollection = Anki_Generic_Empty()
            case let .deck(id, _):
                limit.deckID = id
        }

        do {
            let count = try await service.exportAnkiPackage(outPath: outPath, options: opts, limit: limit)
            exportedCount = count
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }
}
