import Foundation

extension RemoteAnkiService {
    public func setBrowserTableNotesMode(_ enabled: Bool) async throws {
        var req = Anki_Config_SetConfigBoolRequest()
        req.key = .browserTableShowNotesMode
        req.value = enabled
        req.undoable = false
        let _: Anki_Collection_OpChanges = try await command(
            service: ServiceIndex.config,
            method: ConfigMethod.setConfigBool,
            input: req
        )
    }

    public func getPreferences() async throws -> Anki_Config_Preferences {
        try await command(
            service: ServiceIndex.config,
            method: ConfigMethod.getPreferences,
            input: Anki_Generic_Empty()
        )
    }

    public func setPreferences(prefs: Anki_Config_Preferences) async throws {
        let _: Anki_Generic_Empty = try await command(
            service: ServiceIndex.config,
            method: ConfigMethod.setPreferences,
            input: prefs
        )
    }
}
