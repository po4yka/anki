import AppleBridgeCore
import AppleSharedUI
import Foundation
import Observation

@Observable
@MainActor
final class NoteLinksModel {
    var relatedNotes: [NoteLink] = []
    var isLoading: Bool = false
    var error: String?

    private let atlas: any AtlasServiceProtocol

    init(atlas: any AtlasServiceProtocol) {
        self.atlas = atlas
    }

    func load(noteId: Int64, limit: Int = 12) async {
        isLoading = true
        error = nil
        do {
            let response = try await atlas.getNoteLinks(noteId: noteId, limit: limit)
            relatedNotes = response.relatedNotes
        } catch {
            relatedNotes = []
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
