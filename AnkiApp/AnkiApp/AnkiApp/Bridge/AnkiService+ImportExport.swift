// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
    func importAnkiPackage(path: String,
                           options: Anki_ImportExport_ImportAnkiPackageOptions) async throws
        -> Anki_ImportExport_ImportResponse {
        var req = Anki_ImportExport_ImportAnkiPackageRequest()
        req.packagePath = path
        req.options = options
        return try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.importAnkiPackage,
            input: req
        )
    }

    func exportAnkiPackage(
        outPath: String,
        options: Anki_ImportExport_ExportAnkiPackageOptions,
        limit: Anki_ImportExport_ExportLimit
    ) async throws -> UInt32 {
        var req = Anki_ImportExport_ExportAnkiPackageRequest()
        req.outPath = outPath
        req.options = options
        req.limit = limit
        let response: Anki_Generic_UInt32 = try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.exportAnkiPackage,
            input: req
        )
        return response.val
    }

    func getCsvMetadata(
        path: String,
        delimiter: Anki_ImportExport_CsvMetadata.Delimiter?,
        notetypeId: Int64?,
        deckId: Int64?,
        isHtml: Bool?
    ) async throws -> Anki_ImportExport_CsvMetadata {
        var req = Anki_ImportExport_CsvMetadataRequest()
        req.path = path
        if let delimiter { req.delimiter = delimiter }
        if let notetypeId { req.notetypeID = notetypeId }
        if let deckId { req.deckID = deckId }
        if let isHtml { req.isHTML = isHtml }
        return try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.getCsvMetadata,
            input: req
        )
    }

    func importCsv(path: String,
                   metadata: Anki_ImportExport_CsvMetadata) async throws -> Anki_ImportExport_ImportResponse {
        var req = Anki_ImportExport_ImportCsvRequest()
        req.path = path
        req.metadata = metadata
        return try backend.command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.importCsv,
            input: req
        )
    }
}
