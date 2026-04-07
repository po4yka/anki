import SwiftUI
import AVFoundation

struct ReviewerView: View {
    @Environment(AppState.self) private var appState
    @State private var model: ReviewerModel?
    @State private var showingAnswer = false
    @State private var audioPlayer: AVPlayer?
    @State private var editingNoteId: Int64? = nil
    @State private var showCardInfo = false
    @State private var autoShowTask: Task<Void, Never>?
    @State private var autoAdvanceTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                if model.queuedCards?.cards.isEmpty ?? true, !model.isLoading {
                    CongratsView(deckId: model.lastDeckId) {
                        dismiss()
                    }
                } else {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            toolbar(model: model)

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

                                if showingAnswer, let comparison = model.comparisonHTML {
                                    TypeAnswerComparison(html: comparison)
                                        .padding(.horizontal)
                                }
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            Divider()

                            bottomBar(model: model)
                        }

                        if showCardInfo, let stats = model.cardStats {
                            Divider()
                            CardInfoSidebar(stats: stats) {
                                showCardInfo = false
                            }
                            .frame(width: 260)
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
        .onChange(of: showingAnswer) { _, newValue in
            cancelAutoTasks()
            guard let model else { return }
            if newValue {
                if model.isTypeAnswerCard {
                    Task { await model.compareTypedAnswer() }
                }
                autoAdvanceTask = model.scheduleAutoAdvance()
                if let autoAdvanceTask {
                    Task {
                        await autoAdvanceTask.value
                        guard !autoAdvanceTask.isCancelled else { return }
                        if let rating = model.autoAnswerRating() {
                            performAnswer(model: model, rating: rating)
                        }
                    }
                }
            } else {
                autoShowTask = model.scheduleAutoShowAnswer()
                if let autoShowTask {
                    Task {
                        await autoShowTask.value
                        guard !autoShowTask.isCancelled else { return }
                        showingAnswer = true
                    }
                }
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

    // MARK: - Toolbar

    private func toolbar(model: ReviewerModel) -> some View {
        HStack {
            ReviewProgress(
                newCount: model.queuedCards?.newCount ?? 0,
                learnCount: model.queuedCards?.learningCount ?? 0,
                reviewCount: model.queuedCards?.reviewCount ?? 0
            )

            if model.showTimer {
                Text(model.formattedTime)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

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

            Button {
                if !showCardInfo {
                    Task { await model.loadCardStats() }
                }
                showCardInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Card Info")

            flagMenu(model: model)

            moreMenu(model: model)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private func bottomBar(model: ReviewerModel) -> some View {
        VStack(spacing: 8) {
            if model.isTypeAnswerCard, !showingAnswer {
                TextField("Type your answer...", text: Binding(
                    get: { model.typedAnswer },
                    set: { model.typedAnswer = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    showingAnswer = true
                }
                .padding(.horizontal)
            }

            if showingAnswer {
                AnswerBar { rating in
                    performAnswer(model: model, rating: rating)
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

    // MARK: - Helpers

    private func performAnswer(model: ReviewerModel, rating: Anki_Scheduler_CardAnswer.Rating) {
        cancelAutoTasks()
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

    private func cancelAutoTasks() {
        autoShowTask?.cancel()
        autoShowTask = nil
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
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

// MARK: - Type Answer Comparison

private struct TypeAnswerComparison: View {
    let html: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Answer Comparison")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(attributedComparison)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var attributedComparison: AttributedString {
        // The backend returns HTML-formatted comparison; display as plain text fallback
        let cleaned = html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return AttributedString(cleaned)
    }
}

// MARK: - Card Info Sidebar

private struct CardInfoSidebar: View {
    let stats: Anki_Stats_CardStatsResponse
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Card Info")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow("Card Type", stats.cardType)
                    infoRow("Note Type", stats.notetype)
                    infoRow("Deck", stats.deck)

                    Divider()

                    infoRow("Interval", stats.interval > 0 ? "\(stats.interval) days" : "N/A")
                    infoRow("Ease", stats.ease > 0 ? "\(stats.ease / 10)%" : "N/A")
                    infoRow("Reviews", "\(stats.reviews)")
                    infoRow("Lapses", "\(stats.lapses)")

                    Divider()

                    infoRow("Created", formatTimestamp(stats.added))
                    if stats.hasDueDate {
                        infoRow("Due", formatTimestamp(stats.dueDate))
                    }
                    if stats.hasFirstReview {
                        infoRow("First Review", formatTimestamp(stats.firstReview))
                    }
                    if stats.hasLatestReview {
                        infoRow("Latest Review", formatTimestamp(stats.latestReview))
                    }

                    Divider()

                    infoRow("Average Time", String(format: "%.1fs", stats.averageSecs))
                    infoRow("Total Time", String(format: "%.1fs", stats.totalSecs))
                }
                .padding()
            }
        }
        .background(.background)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return "N/A" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
