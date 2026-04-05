import Foundation
import Observation

@Observable
@MainActor
final class CardGeneratorModel {
    var sourceText: String = ""
    var topic: String = ""
    var preview: GeneratePreview? = nil
    var isGenerating: Bool = false
    var error: String? = nil

    private let atlas: AtlasService

    init(atlas: AtlasService) {
        self.atlas = atlas
    }

    func generatePreview() async {
        guard !sourceText.isEmpty else { return }
        isGenerating = true
        error = nil
        let request = GeneratePreviewRequest(
            sourceText: sourceText,
            topic: topic.isEmpty ? nil : topic
        )
        do {
            let result: GeneratePreview = try await atlas.command(method: "generate_preview", request: request)
            preview = result
        } catch {
            self.error = error.localizedDescription
            preview = nil
        }
        isGenerating = false
    }
}
