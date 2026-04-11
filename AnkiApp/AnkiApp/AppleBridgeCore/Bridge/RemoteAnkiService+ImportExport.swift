import Foundation

extension RemoteAnkiService {
    public func importAnkiPackage(
        path: String,
        options: Anki_ImportExport_ImportAnkiPackageOptions
    ) async throws -> Anki_ImportExport_ImportResponse {
        var req = Anki_ImportExport_ImportAnkiPackageRequest()
        req.packagePath = path
        req.options = options
        return try await command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.importAnkiPackage,
            input: req
        )
    }

    public func exportAnkiPackage(
        outPath: String,
        options: Anki_ImportExport_ExportAnkiPackageOptions,
        limit: Anki_ImportExport_ExportLimit
    ) async throws -> UInt32 {
        var req = Anki_ImportExport_ExportAnkiPackageRequest()
        req.outPath = outPath
        req.options = options
        req.limit = limit
        let response: Anki_Generic_UInt32 = try await command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.exportAnkiPackage,
            input: req
        )
        return response.val
    }

    public func getCsvMetadata(
        path: String,
        delimiter: Anki_ImportExport_CsvMetadata.Delimiter?,
        notetypeId: Int64?,
        deckId: Int64?,
        isHtml: Bool?
    ) async throws -> Anki_ImportExport_CsvMetadata {
        var req = Anki_ImportExport_CsvMetadataRequest()
        req.path = path
        if let delimiter {
            req.delimiter = delimiter
        }
        if let notetypeId {
            req.notetypeID = notetypeId
        }
        if let deckId {
            req.deckID = deckId
        }
        if let isHtml {
            req.isHtml = isHtml
        }
        return try await command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.getCsvMetadata,
            input: req
        )
    }

    public func importCsv(
        path: String,
        metadata: Anki_ImportExport_CsvMetadata
    ) async throws -> Anki_ImportExport_ImportResponse {
        var req = Anki_ImportExport_ImportCsvRequest()
        req.path = path
        req.metadata = metadata
        return try await command(
            service: ServiceIndex.importExport,
            method: ImportExportMethod.importCsv,
            input: req
        )
    }
}
