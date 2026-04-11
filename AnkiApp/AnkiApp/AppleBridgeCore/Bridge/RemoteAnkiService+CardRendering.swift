import Foundation

public extension RemoteAnkiService {
    func extractAvTags(text: String, questionSide: Bool) async throws -> Anki_CardRendering_ExtractAvTagsResponse {
        var req = Anki_CardRendering_ExtractAvTagsRequest()
        req.text = text
        req.questionSide = questionSide
        return try await command(
            service: ServiceIndex.cardRendering,
            method: CardRenderingMethod.extractAvTags,
            input: req
        )
    }
}
