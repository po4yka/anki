import Foundation

public extension RemoteAnkiService {
    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = path
        req.mediaFolderPath = mediaFolder
        req.mediaDbPath = mediaDb
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.openCollection,
            input: req
        )
        await sessionManager?.recordRemoteCollectionState(
            path: path,
            mediaFolder: mediaFolder,
            mediaDb: mediaDb
        )
    }

    func closeCollection(downgrade: Bool) async throws {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgrade
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.closeCollection,
            input: req
        )
        await sessionManager?.clearRemoteCollectionState()
    }

    func getUndoStatus() async throws -> Anki_Collection_UndoStatus {
        try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.getUndoStatus,
            input: Anki_Generic_Empty()
        )
    }

    func undo() async throws -> Anki_Collection_OpChangesAfterUndo {
        try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.undo,
            input: Anki_Generic_Empty()
        )
    }

    func redo() async throws -> Anki_Collection_OpChangesAfterUndo {
        try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.redo,
            input: Anki_Generic_Empty()
        )
    }

    func createBackup(backupFolder: String, force: Bool, waitForCompletion: Bool) async throws -> Bool {
        var req = Anki_Collection_CreateBackupRequest()
        req.backupFolder = backupFolder
        req.force = force
        req.waitForCompletion = waitForCompletion
        let response: Anki_Generic_Bool = try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.createBackup,
            input: req
        )
        return response.val
    }

    func awaitBackupCompletion() async throws -> Bool {
        let response: Anki_Generic_Bool = try await command(
            service: ServiceIndex.collection,
            method: CollectionMethod.awaitBackupCompletion,
            input: Anki_Generic_Empty()
        )
        return response.val
    }
}
