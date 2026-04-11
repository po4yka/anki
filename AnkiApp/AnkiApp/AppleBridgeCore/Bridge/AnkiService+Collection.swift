// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

public extension AnkiService {
    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = path
        req.mediaFolderPath = mediaFolder
        req.mediaDbPath = mediaDb
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.openCollection,
            input: req
        )
    }

    func closeCollection(downgrade: Bool) async throws {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgrade
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.closeCollection,
            input: req
        )
    }

    func getUndoStatus() async throws -> Anki_Collection_UndoStatus {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.getUndoStatus,
            input: req
        )
    }

    func undo() async throws -> Anki_Collection_OpChangesAfterUndo {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.undo,
            input: req
        )
    }

    func redo() async throws -> Anki_Collection_OpChangesAfterUndo {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.redo,
            input: req
        )
    }

    func createBackup(backupFolder: String, force: Bool, waitForCompletion: Bool) async throws -> Bool {
        var req = Anki_Collection_CreateBackupRequest()
        req.backupFolder = backupFolder
        req.force = force
        req.waitForCompletion = waitForCompletion
        let response: Anki_Generic_Bool = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.createBackup,
            input: req
        )
        return response.val
    }

    func awaitBackupCompletion() async throws -> Bool {
        let req = Anki_Generic_Empty()
        let response: Anki_Generic_Bool = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.awaitBackupCompletion,
            input: req
        )
        return response.val
    }
}
