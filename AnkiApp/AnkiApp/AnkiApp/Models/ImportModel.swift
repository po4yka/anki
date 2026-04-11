import AppleBridgeCore
import AppleSharedUI
import Foundation
import Observation

@Observable
@MainActor
final class ImportModel {
    var isImporting = false
    var importResult: ImportResult?
    var errorMessage: String?
    var options = ImportOptions()

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    struct ImportOptions {
        var mergeNotetypes = true
        var withScheduling = true
        var withDeckConfigs = true
        var updateNotes: Anki_ImportExport_ImportAnkiPackageUpdateCondition = .ifNewer
        var updateNotetypes: Anki_ImportExport_ImportAnkiPackageUpdateCondition = .ifNewer
    }

    struct ImportResult {
        let newNotes: Int
        let updatedNotes: Int
        let duplicateNotes: Int
        let conflictingNotes: Int
        let foundNotes: UInt32
    }

    func importPackage(path: String) async {
        isImporting = true
        importResult = nil
        errorMessage = nil

        var opts = Anki_ImportExport_ImportAnkiPackageOptions()
        opts.mergeNotetypes = options.mergeNotetypes
        opts.withScheduling = options.withScheduling
        opts.withDeckConfigs = options.withDeckConfigs
        opts.updateNotes = options.updateNotes
        opts.updateNotetypes = options.updateNotetypes

        do {
            let response = try await service.importAnkiPackage(path: path, options: opts)
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
