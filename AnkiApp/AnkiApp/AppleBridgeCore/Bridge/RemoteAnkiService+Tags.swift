import Foundation

extension RemoteAnkiService {
    public func allTags() async throws -> Anki_Generic_StringList {
        try await command(
            service: ServiceIndex.tags,
            method: TagsMethod.allTags,
            input: Anki_Generic_Empty()
        )
    }
}
