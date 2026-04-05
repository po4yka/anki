import SwiftUI

struct ReviewerView: View {
    @Environment(AppState.self) private var appState
    @State private var model: ReviewerModel?
    @State private var showingAnswer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                if model.queuedCards?.cards.isEmpty ?? true, !model.isLoading {
                    CongratsView {
                        dismiss()
                    }
                } else {
                    VStack(spacing: 0) {
                        ReviewProgress(
                            newCount: model.queuedCards?.newCount ?? 0,
                            learnCount: model.queuedCards?.learningCount ?? 0,
                            reviewCount: model.queuedCards?.reviewCount ?? 0
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)

                        Divider()

                        if model.currentCardHTML != nil {
                            CardWebView(
                                html: cardHTML,
                                css: "",
                                baseURL: nil
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        Divider()

                        if showingAnswer {
                            AnswerBar { rating in
                                showingAnswer = false
                                if let card = model.queuedCards?.cards.first,
                                   card.hasStates {
                                    let states = card.states
                                    let newState: Anki_Scheduler_SchedulingState = {
                                        switch rating {
                                        case .again: return states.again
                                        case .hard: return states.hard
                                        case .good: return states.good
                                        case .easy: return states.easy
                                        default: return states.good
                                        }
                                    }()
                                    Task {
                                        await model.answerCard(
                                            cardId: card.card.id,
                                            rating: rating,
                                            currentState: states.current,
                                            newState: newState
                                        )
                                    }
                                }
                            }
                            .padding()
                        } else {
                            Button("Show Answer") {
                                showingAnswer = true
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
                model = ReviewerModel(service: appState.service)
                Task { await model?.loadQueue() }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private var cardHTML: String {
        guard let rendered = model?.currentCardHTML else { return "" }
        let nodes = showingAnswer ? rendered.answerNodes : rendered.questionNodes
        return nodes.map { node -> String in
            if !node.text.isEmpty { return node.text }
            return node.replacement.currentText
        }.joined()
    }
}

#Preview {
    ReviewerView()
        .environment(AppState())
}
