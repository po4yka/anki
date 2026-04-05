import SwiftUI

struct ReviewerView: View {
    let deckId: Int64
    @Environment(AppState.self) private var appState
    @State private var model: ReviewerModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                if model.isFinished {
                    CongratsView {
                        dismiss()
                    }
                } else {
                    VStack(spacing: 0) {
                        ReviewProgress(model: model)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        Divider()

                        if let card = model.currentCard {
                            CardWebView(
                                html: model.showingAnswer ? card.answerHTML : card.questionHTML,
                                css: card.css,
                                baseURL: appState.mediaFolderURL
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        Divider()

                        if model.showingAnswer {
                            AnswerBar(model: model)
                                .padding()
                        } else {
                            Button("Show Answer") {
                                model.showAnswer()
                            }
                            .keyboardShortcut(.space, modifiers: [])
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                    }
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if model == nil {
                model = ReviewerModel(service: appState.service, deckId: deckId)
                Task { await model?.loadNextCard() }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .ankiErrorAlert($model?.error)
    }
}

#Preview {
    ReviewerView(deckId: 1)
        .environment(AppState())
}
