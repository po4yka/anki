// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
import Foundation

extension AnkiService {
    public func addMediaFile(desiredName: String, data: Data) async throws -> String {
        var req = Anki_Media_AddMediaFileRequest()
        req.desiredName = desiredName
        req.data = data
        let response: Anki_Generic_String = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.addMediaFile,
            input: req
        )
        return response.val
    }

    public func checkMedia() async throws -> Anki_Media_CheckMediaResponse {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.checkMedia,
            input: req
        )
    }

    public func trashMediaFiles(filenames: [String]) async throws {
        var req = Anki_Media_TrashMediaFilesRequest()
        req.fnames = filenames
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.trashMediaFiles,
            input: req
        )
    }

    public func emptyTrash() async throws {
        let req = Anki_Generic_Empty()
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.emptyTrash,
            input: req
        )
    }

    public func restoreTrash() async throws {
        let req = Anki_Generic_Empty()
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.media,
            method: MediaMethod.restoreTrash,
            input: req
        )
    }
}
#endif
