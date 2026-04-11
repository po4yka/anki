// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

extension AnkiService {
    public func setBrowserTableNotesMode(_ enabled: Bool) async throws {
        var req = Anki_Config_SetConfigBoolRequest()
        req.key = .browserTableShowNotesMode
        req.value = enabled
        req.undoable = false
        let _: Anki_Collection_OpChanges = try backend.command(
            service: ServiceIndex.config,
            method: ConfigMethod.setConfigBool,
            input: req
        )
    }

    public func getPreferences() async throws -> Anki_Config_Preferences {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.config,
            method: ConfigMethod.getPreferences,
            input: req
        )
    }

    public func setPreferences(prefs: Anki_Config_Preferences) async throws {
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.config,
            method: ConfigMethod.setPreferences,
            input: prefs
        )
    }
}
