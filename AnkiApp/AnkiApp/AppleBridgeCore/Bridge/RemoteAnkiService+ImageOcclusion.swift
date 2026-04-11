import Foundation

extension RemoteAnkiService {
    public func getImageForOcclusion(path: String) async throws -> Anki_ImageOcclusion_GetImageForOcclusionResponse {
        var req = Anki_ImageOcclusion_GetImageForOcclusionRequest()
        req.path = path
        return try await command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.getImageForOcclusion,
            input: req
        )
    }

    public func getImageOcclusionNote(noteId: Int64) async throws
        -> Anki_ImageOcclusion_GetImageOcclusionNoteResponse {
        var req = Anki_ImageOcclusion_GetImageOcclusionNoteRequest()
        req.noteID = noteId
        return try await command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.getImageOcclusionNote,
            input: req
        )
    }

    public func addImageOcclusionNote(request: Anki_ImageOcclusion_AddImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges {
        try await command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.addImageOcclusionNote,
            input: request
        )
    }

    public func updateImageOcclusionNote(request: Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest) async throws
        -> Anki_Collection_OpChanges {
        try await command(
            service: ServiceIndex.imageOcclusion,
            method: ImageOcclusionMethod.updateImageOcclusionNote,
            input: request
        )
    }
}
