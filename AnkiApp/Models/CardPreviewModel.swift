import Foundation
import Observation

@Observable
@MainActor
final class CardPreviewModel {
    var questionHTML: String = ""
    var answerHTML: String = ""
    var css: String = ""
    var showingAnswer: Bool = false
    var isLoading: Bool = false
    var selectedCardId: Int64?

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadCard(cardId: Int64) async {
        guard cardId != selectedCardId || questionHTML.isEmpty else { return }
        selectedCardId = cardId
        showingAnswer = false
        isLoading = true
        defer { isLoading = false }
        do {
            let rendered = try await service.renderExistingCard(cardId: cardId, browser: true)
            questionHTML = rendered.questionNodes.map { node -> String in
                node.text.isEmpty ? node.replacement.currentText : node.text
            }.joined()
            answerHTML = rendered.answerNodes.map { node -> String in
                node.text.isEmpty ? node.replacement.currentText : node.text
            }.joined()
            css = rendered.css
        } catch {
            questionHTML = ""
            answerHTML = ""
            css = ""
        }
    }

    func flipSide() {
        showingAnswer.toggle()
    }
}
