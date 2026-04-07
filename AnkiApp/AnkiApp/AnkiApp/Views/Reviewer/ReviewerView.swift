import SwiftUI
import AVFoundation

struct ReviewerView: View {
    @Environment(AppState.self) private var appState
    @State private var model: ReviewerModel?
    @State private var showingAnswer = false
    @State private var audioPlayer: AVPlayer?
    @State private var editingNoteId: Int64? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                if model.queuedCards?.cards.isEmpty ?? true, !model.isLoading {
                    CongratsView(deckId: model.lastDeckId) {
                        dismiss()
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            ReviewProgress(
                                newCount: model.queuedCards?.newCount ?? 0,
                                learnCount: model.queuedCards?.learningCount ?? 0,
                                reviewCount: model.queuedCards?.reviewCount ?? 0
                            )

                            Spacer()

                            if let undoLabel = model.undoLabel {
                                Button {
                                    Task { await model.undoLastAnswer() }
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .help(undoLabel)
                                .keyboardShortcut("z", modifiers: .command)
                            }

                            Button {
                                if let noteId = model.queuedCards?.cards.first?.card.noteID {
                                    editingNoteId = noteId
                                }
                            } label: {
                                Image(systemName: "pencil.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Edit Note")

                            if !model.currentAvTags.isEmpty {
                                Button {
                                    replayAudio()
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                }
                                .buttonStyle(.borderless)
                                .help("Replay Audio")
                            }

                            flagMenu(model: model)

                            moreMenu(model: model)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        Divider()

                        if model.currentCardHTML != nil {
                            CardWebView(
                                html: cardHTML,
                                css: "",
                                baseURL: appState.mediaFolderURL,
                                onPlayAudio: { filename in
                                    playAudioFile(filename)
                                }
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
        .sheet(item: Binding(
            get: { editingNoteId.map { ReviewEditNoteItem(noteId: $0) } },
            set: { editingNoteId = $0?.noteId }
        )) { item in
            NavigationStack {
                NoteEditorView(noteId: item.noteId)
            }
        }
    }

    private var cardHTML: String {
        guard let rendered = model?.currentCardHTML else { return "" }
        let nodes = showingAnswer ? rendered.answerNodes : rendered.questionNodes
        return nodes.map { node -> String in
            if !node.text.isEmpty { return node.text }
            return node.replacement.currentText
        }.joined()
    }

    private func playAudioFile(_ filename: String) {
        guard let mediaFolder = appState.mediaFolderURL else { return }
        let fileURL = mediaFolder.appendingPathComponent(filename)
        audioPlayer = AVPlayer(url: fileURL)
        audioPlayer?.play()
    }

    private func flagMenu(model: ReviewerModel) -> some View {
        Menu {
            Button {
                Task { await model.flagCard(flag: 0) }
            } label: {
                Label("No Flag", systemImage: "flag.slash")
            }
            .keyboardShortcut("1", modifiers: .command)

            Button {
                Task { await model.flagCard(flag: 1) }
            } label: {
                Label("Red", systemImage: "flag.fill")
            }
            .keyboardShortcut("2", modifiers: .command)

            Button {
                Task { await model.flagCard(flag: 2) }
            } label: {
                Label("Orange", systemImage: "flag.fill")
            }
            .keyboardShortcut("3", modifiers: .command)

            Button {
                Task { await model.flagCard(flag: 3) }
            } label: {
                Label("Green", systemImage: "flag.fill")
            }
            .keyboardShortcut("4", modifiers: .command)

            Button {
                Task { await model.flagCard(flag: 4) }
            } label: {
                Label("Blue", systemImage: "flag.fill")
            }
            .keyboardShortcut("5", modifiers: .command)
        } label: {
            Image(systemName: model.currentFlag > 0 ? "flag.fill" : "flag")
                .foregroundStyle(flagColor(model.currentFlag))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Flag Card")
    }

    private func moreMenu(model: ReviewerModel) -> some View {
        Menu {
            Button("Bury Card") {
                Task { await model.buryCard() }
            }
            Button("Bury Note") {
                Task { await model.buryNote() }
            }
            Divider()
            Button("Suspend Card") {
                Task { await model.suspendCard() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More Actions")
    }

    private func flagColor(_ flag: UInt32) -> Color {
        switch flag {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        default: return .primary
        }
    }

    private func replayAudio() {
        guard let model else { return }
        for tag in model.currentAvTags {
            if case .soundOrVideo(let filename) = tag.value {
                playAudioFile(filename)
                return
            }
        }
    }
}

private struct ReviewEditNoteItem: Identifiable {
    let noteId: Int64
    var id: Int64 { noteId }
}

#Preview {
    ReviewerView()
        .environment(AppState())
}
