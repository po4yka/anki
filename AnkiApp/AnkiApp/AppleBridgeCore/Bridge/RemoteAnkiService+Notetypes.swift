import Foundation

public extension RemoteAnkiService {
    func getNotetypeNames() async throws -> Anki_Notetypes_NotetypeNames {
        try await command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetypeNames,
            input: Anki_Generic_Empty()
        )
    }

    func getNotetype(id: Int64) async throws -> Anki_Notetypes_Notetype {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = id
        return try await command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetype,
            input: req
        )
    }

    func addNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChangesWithId {
        try await command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.addNotetype,
            input: notetype
        )
    }

    func updateNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChanges {
        try await command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.updateNotetype,
            input: notetype
        )
    }

    func removeNotetype(id: Int64) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = id
        return try await command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.removeNotetype,
            input: req
        )
    }

    func getNotetypeNamesAndCounts() async throws -> Anki_Notetypes_NotetypeUseCounts {
        try await command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetypeNamesAndCounts,
            input: Anki_Generic_Empty()
        )
    }
}
