import SwiftUI

struct DeckOverviewView: View {
    let node: Anki_Decks_DeckTreeNode
    let service: AnkiServiceProtocol
    @Environment(AppState.self) private var appState
    @State private var deck: Anki_Decks_Deck?
    @State private var showingReviewer = false
    @State private var showingCustomStudy = false
    @State private var error: AnkiError?
    @Environment(\.dismiss) private var dismiss

    private var description: String {
        deck?.normal.description_p ?? ""
    }

    private var isFiltered: Bool {
        node.filtered
    }

    private var totalDue: UInt32 {
        node.newCount + node.learnCount + node.reviewCount
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Text(node.name)
                    .font(.largeTitle.bold())

                if !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 24) {
                    CountBadge(label: "New", cardCount: node.newCount, color: .blue)
                    CountBadge(label: "Learn", cardCount: node.learnCount, color: .orange)
                    CountBadge(label: "Review", cardCount: node.reviewCount, color: .green)
                }

                Divider()
                    .frame(maxWidth: 300)

                HStack(spacing: 8) {
                    Text("\(node.totalInDeck) cards in deck")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                VStack(spacing: 12) {
                    Button {
                        showingReviewer = true
                    } label: {
                        Text("Study Now")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(totalDue == 0)

                    if isFiltered {
                        HStack(spacing: 12) {
                            Button("Rebuild") {
                                Task {
                                    do {
                                        _ = try await service.rebuildFilteredDeck(deckId: node.deckID)
                                    } catch let ankiError as AnkiError {
                                        error = ankiError
                                    } catch {}
                                }
                            }
                            Button("Empty") {
                                Task {
                                    do {
                                        _ = try await service.emptyFilteredDeck(deckId: node.deckID)
                                    } catch let ankiError as AnkiError {
                                        error = ankiError
                                    } catch {}
                                }
                            }
                        }
                    } else {
                        Button("Custom Study...") {
                            showingCustomStudy = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                deck = try await service.getDeck(id: node.deckID)
            } catch {}
        }
        .sheet(isPresented: $showingReviewer) {
            ReviewerView()
                .environment(appState)
        }
        .sheet(isPresented: $showingCustomStudy) {
            CustomStudyView(service: service, deckId: node.deckID)
        }
        .ankiErrorAlert(Binding(
            get: { error },
            set: { error = $0 }
        ))
    }
}

private struct CountBadge: View {
    let label: String
    let cardCount: UInt32
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(cardCount)")
                .font(.title.bold())
                .foregroundStyle(cardCount != 0 ? color : .secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}
