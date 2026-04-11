// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
import Foundation

extension AnkiService {
    func addNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Tags_NoteIdsAndTagsRequest()
        req.noteIds = noteIds
        req.tags = tags
        return try backend.command(
            service: ServiceIndex.tags,
            method: TagsMethod.addNoteTags,
            input: req
        )
    }

    func removeNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Tags_NoteIdsAndTagsRequest()
        req.noteIds = noteIds
        req.tags = tags
        return try backend.command(
            service: ServiceIndex.tags,
            method: TagsMethod.removeNoteTags,
            input: req
        )
    }

    func allTags() async throws -> Anki_Generic_StringList {
        let req = Anki_Generic_Empty()
        return try backend.command(
            service: ServiceIndex.tags,
            method: TagsMethod.allTags,
            input: req
        )
    }
}
#endif
