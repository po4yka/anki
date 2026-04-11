import Foundation

extension RemoteAnkiService {
    public func addMediaFile(desiredName: String, data: Data) async throws -> String {
        var req = Anki_Media_AddMediaFileRequest()
        req.desiredName = desiredName
        req.data = data
        let response: Anki_Generic_String = try await command(
            service: ServiceIndex.media,
            method: MediaMethod.addMediaFile,
            input: req
        )
        return response.val
    }

    public func checkMedia() async throws -> Anki_Media_CheckMediaResponse {
        try await command(
            service: ServiceIndex.media,
            method: MediaMethod.checkMedia,
            input: Anki_Generic_Empty()
        )
    }

    public func trashMediaFiles(filenames: [String]) async throws {
        var req = Anki_Media_TrashMediaFilesRequest()
        req.fnames = filenames
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.media,
            method: MediaMethod.trashMediaFiles,
            input: req
        )
    }

    public func emptyTrash() async throws {
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.media,
            method: MediaMethod.emptyTrash,
            input: Anki_Generic_Empty()
        )
    }

    public func restoreTrash() async throws {
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.media,
            method: MediaMethod.restoreTrash,
            input: Anki_Generic_Empty()
        )
    }
}
