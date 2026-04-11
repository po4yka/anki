// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

public extension AnkiService {
    func getNotetypeNames() async throws -> Anki_Notetypes_NotetypeNames {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetypeNames,
            input: req
        )
    }

    func getNotetype(id: Int64) async throws -> Anki_Notetypes_Notetype {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = id
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetype,
            input: req
        )
    }

    func addNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChangesWithId {
        try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.addNotetype,
            input: notetype
        )
    }

    func updateNotetype(notetype: Anki_Notetypes_Notetype) async throws -> Anki_Collection_OpChanges {
        try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.updateNotetype,
            input: notetype
        )
    }

    func removeNotetype(id: Int64) async throws -> Anki_Collection_OpChanges {
        var req = Anki_Notetypes_NotetypeId()
        req.ntid = id
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.removeNotetype,
            input: req
        )
    }

    func getNotetypeNamesAndCounts() async throws -> Anki_Notetypes_NotetypeUseCounts {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.notetypes,
            method: NotetypesMethod.getNotetypeNamesAndCounts,
            input: req
        )
    }
}
