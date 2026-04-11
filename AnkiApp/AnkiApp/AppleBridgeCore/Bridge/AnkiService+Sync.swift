// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
    public func syncLogin(username: String, password: String) async throws -> Anki_Sync_SyncAuth {
        var req = Anki_Sync_SyncLoginRequest()
        req.username = username
        req.password = password
        return try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncLogin,
            input: req
        )
    }

    public func syncStatus(auth: Anki_Sync_SyncAuth) async throws -> Anki_Sync_SyncStatusResponse {
        try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncStatus,
            input: auth
        )
    }

    public func syncCollection(auth: Anki_Sync_SyncAuth, syncMedia: Bool) async throws -> Anki_Sync_SyncCollectionResponse {
        var req = Anki_Sync_SyncCollectionRequest()
        req.auth = auth
        req.syncMedia = syncMedia
        return try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncCollection,
            input: req
        )
    }

    public func fullUploadOrDownload(auth: Anki_Sync_SyncAuth, upload: Bool, serverUsn: Int32?) async throws {
        var req = Anki_Sync_FullUploadOrDownloadRequest()
        req.auth = auth
        req.upload = upload
        if let serverUsn {
            req.serverUsn = serverUsn
        }
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.fullUploadOrDownload,
            input: req
        )
    }

    public func syncMedia(auth: Anki_Sync_SyncAuth) async throws {
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.sync,
            method: SyncMethod.syncMedia,
            input: auth
        )
    }
}
