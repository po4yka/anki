import AppleBridgeCore
import AppleSharedUI
import Foundation
import Observation

@Observable
@MainActor
final class CsvImportModel {
    var isLoading = false
    var isImporting = false
    var metadata: Anki_ImportExport_CsvMetadata?
    var importResult: ImportResult?
    var errorMessage: String?
    var selectedDelimiter: Anki_ImportExport_CsvMetadata.Delimiter = .tab
    var isHtml = false
    var dupeResolution: Anki_ImportExport_CsvMetadata.DupeResolution = .update

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    struct ImportResult {
        let newNotes: Int
        let updatedNotes: Int
        let duplicateNotes: Int
        let conflictingNotes: Int
        let foundNotes: UInt32
    }

    func loadMetadata(path: String) async {
        isLoading = true
        metadata = nil
        importResult = nil
        errorMessage = nil

        do {
            let meta = try await service.getCsvMetadata(
                path: path,
                delimiter: nil,
                notetypeId: nil,
                deckId: nil,
                isHtml: nil
            )
            metadata = meta
            selectedDelimiter = meta.delimiter
            isHtml = meta.isHtml
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reloadMetadata(path: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let meta = try await service.getCsvMetadata(
                path: path,
                delimiter: selectedDelimiter,
                notetypeId: nil,
                deckId: nil,
                isHtml: isHtml
            )
            metadata = meta
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func importCsv(path: String) async {
        guard var meta = metadata else { return }

        isImporting = true
        importResult = nil
        errorMessage = nil

        meta.delimiter = selectedDelimiter
        meta.isHtml = isHtml
        meta.dupeResolution = dupeResolution

        do {
            let response = try await service.importCsv(path: path, metadata: meta)
            if response.hasLog {
                importResult = ImportResult(
                    newNotes: response.log.new.count,
                    updatedNotes: response.log.updated.count,
                    duplicateNotes: response.log.duplicate.count,
                    conflictingNotes: response.log.conflicting.count,
                    foundNotes: response.log.foundNotes
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }
}
