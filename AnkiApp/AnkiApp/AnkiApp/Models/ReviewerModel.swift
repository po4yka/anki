import Foundation
import Observation

// swiftlint:disable file_length

enum TypeAnswerKind: Equatable {
    case field(combining: Bool)
    case cloze
}

struct TypeAnswerSpec: Equatable {
    let kind: TypeAnswerKind
    let fieldName: String

    var combining: Bool {
        switch kind {
            case let .field(combining):
                combining
            case .cloze:
                true
        }
    }

    static func parse(questionHTML: String) -> TypeAnswerSpec? {
        guard let range = questionHTML.range(of: #"\[\[type:([^\]]+)\]\]"#, options: .regularExpression) else {
            return nil
        }
        let token = String(questionHTML[range])
            .replacingOccurrences(of: "[[type:", with: "")
            .replacingOccurrences(of: "]]", with: "")

        if let fieldName = token.removingPrefix("cloze:") {
            return TypeAnswerSpec(kind: .cloze, fieldName: fieldName)
        }
        if let fieldName = token.removingPrefix("nc:") {
            return TypeAnswerSpec(kind: .field(combining: false), fieldName: fieldName)
        }
        return TypeAnswerSpec(kind: .field(combining: true), fieldName: token)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class ReviewerModel {
    var queuedCards: Anki_Scheduler_QueuedCards?
    var currentCardHTML: Anki_CardRendering_RenderCardResponse?
    var currentAvTags: [Anki_CardRendering_AVTag] = []
    var questionAvTags: [Anki_CardRendering_AVTag] = []
    var answerAvTags: [Anki_CardRendering_AVTag] = []
    var undoLabel: String?
    var isLoading: Bool = false
    var error: AnkiError?
    var lastDeckId: Int64 = 0

    // Type-answer
    var isTypeAnswerCard: Bool = false
    var typeAnswerField: String = ""
    var typedAnswer: String = ""
    var comparisonHTML: String?
    private var typeAnswerSpec: TypeAnswerSpec?
    private var expectedAnswer: String = ""

    // Auto-advance
    var autoShowAnswerDelay: Float = 0
    var autoAdvanceDelay: Float = 0
    var questionAction: Anki_DeckConfig_DeckConfig.Config.QuestionAction = .showAnswer
    var answerAction: Anki_DeckConfig_DeckConfig.Config.AnswerAction = .buryCard

    // Timer
    var elapsedSeconds: Int = 0
    var showTimer: Bool = false
    private var timerTask: Task<Void, Never>?

    /// Card info
    var cardStats: Anki_Stats_CardStatsResponse?

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadQueue() async {
        isLoading = true
        defer { isLoading = false }
        do {
            queuedCards = try await service.getQueuedCards(fetchLimit: 1)
            if let card = queuedCards?.cards.first?.card {
                lastDeckId = card.deckID
            }
            if let cardId = queuedCards?.cards.first?.card.id {
                currentCardHTML = try await service.renderExistingCard(cardId: cardId)
                await extractAvTags()
                detectTypeAnswer()
                await loadDeckConfig()
                startTimer()
            }
            comparisonHTML = nil
            typedAnswer = ""
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    private func detectTypeAnswer() {
        guard let rendered = currentCardHTML else {
            isTypeAnswerCard = false
            typeAnswerField = ""
            typeAnswerSpec = nil
            expectedAnswer = ""
            return
        }
        let questionHTML = rendered.questionNodes.map { node -> String in
            if !node.text.isEmpty { return node.text }
            return node.replacement.currentText
        }.joined()

        if let spec = TypeAnswerSpec.parse(questionHTML: questionHTML) {
            isTypeAnswerCard = true
            typeAnswerSpec = spec
            typeAnswerField = spec.fieldName
            let templateOrdinal = Int((queuedCards?.cards.first?.card.templateIdx ?? 0) + 1)
            expectedAnswer = expectedTypeAnswer(from: rendered, spec: spec, templateOrdinal: templateOrdinal)
        } else {
            isTypeAnswerCard = false
            typeAnswerField = ""
            typeAnswerSpec = nil
            expectedAnswer = ""
        }
    }

    func compareTypedAnswer() async {
        guard isTypeAnswerCard, let spec = typeAnswerSpec else { return }
        do {
            comparisonHTML = try await service.compareAnswer(
                expected: expectedAnswer,
                provided: typedAnswer,
                combining: spec.combining
            )
        } catch {
            comparisonHTML = nil
        }
    }

    private func expectedTypeAnswer(
        from rendered: Anki_CardRendering_RenderCardResponse,
        spec: TypeAnswerSpec,
        templateOrdinal: Int
    ) -> String {
        let replacementText = rendered.answerNodes
            .compactMap(\.replacementIfPresent)
            .first(where: { $0.fieldName == spec.fieldName })?.currentText
            ?? rendered.questionNodes
            .compactMap(\.replacementIfPresent)
            .first(where: { $0.fieldName == spec.fieldName })?.currentText
            ?? ""

        switch spec.kind {
            case .field:
                return replacementText
            case .cloze:
                return extractClozeText(from: replacementText, ordinal: templateOrdinal)
        }
    }

    private func extractClozeText(from text: String, ordinal: Int) -> String {
        let pattern = #"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        let answers = matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 3,
                  let ordRange = Range(match.range(at: 1), in: text),
                  let textRange = Range(match.range(at: 2), in: text),
                  Int(String(text[ordRange])) == ordinal else {
                return nil
            }
            return String(text[textRange])
        }

        guard !answers.isEmpty else {
            return ""
        }
        if Set(answers).count == 1 {
            return answers[0]
        }
        return answers.joined(separator: ", ")
    }

    private func loadDeckConfig() async {
        guard let card = queuedCards?.cards.first?.card else { return }
        do {
            let update = try await service.getDeckConfigsForUpdate(deckId: card.deckID)
            let configId = update.currentDeck.configID
            if let matched = update.allConfig.first(where: { $0.config.id == configId }),
               matched.hasConfig {
                let inner = matched.config.config
                showTimer = inner.showTimer
                autoShowAnswerDelay = inner.secondsToShowQuestion
                autoAdvanceDelay = inner.secondsToShowAnswer
                questionAction = inner.questionAction
                answerAction = inner.answerAction
            }
        } catch {}
    }

    // MARK: - Timer

    func startTimer() {
        stopTimer()
        elapsedSeconds = 0
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.elapsedSeconds += 1
                }
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    var formattedTime: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func hasReachedTimeLimit(_ timeLimitSecs: UInt32) -> Bool {
        guard timeLimitSecs > 0 else { return false }
        return elapsedSeconds >= Int(timeLimitSecs)
    }

    // MARK: - Auto-advance

    func scheduleAutoShowAnswer() -> Task<Void, Never>? {
        guard autoShowAnswerDelay > 0 else { return nil }
        return Task {
            try? await Task.sleep(for: .seconds(Double(autoShowAnswerDelay)))
            guard !Task.isCancelled else { return }
            // Return -- the view will handle showing the answer
        }
    }

    func autoAnswerRating() -> Anki_Scheduler_CardAnswer.Rating? {
        switch answerAction {
            case .answerAgain: .again
            case .answerHard: .hard
            case .answerGood: .good
            default: nil
        }
    }

    func scheduleAutoAdvance() -> Task<Void, Never>? {
        guard autoAdvanceDelay > 0, autoAnswerRating() != nil else { return nil }
        return Task {
            try? await Task.sleep(for: .seconds(Double(autoAdvanceDelay)))
            guard !Task.isCancelled else { return }
        }
    }

    // MARK: - Card Info

    func loadCardStats() async {
        guard let cardId = queuedCards?.cards.first?.card.id else {
            cardStats = nil
            return
        }
        do {
            cardStats = try await service.getCardStats(cardId: cardId)
        } catch {
            cardStats = nil
        }
    }

    // MARK: - Existing methods

    private func extractAvTags() async {
        guard let rendered = currentCardHTML else {
            questionAvTags = []
            answerAvTags = []
            currentAvTags = []
            return
        }
        let qText = rendered.questionNodes.map { node -> String in
            if !node.text.isEmpty { return node.text }
            return node.replacement.currentText
        }.joined()
        let aText = rendered.answerNodes.map { node -> String in
            if !node.text.isEmpty { return node.text }
            return node.replacement.currentText
        }.joined()
        do {
            let qResponse = try await service.extractAvTags(text: qText, questionSide: true)
            let aResponse = try await service.extractAvTags(text: aText, questionSide: false)
            questionAvTags = qResponse.avTags
            answerAvTags = aResponse.avTags
            currentAvTags = questionAvTags + answerAvTags
        } catch {
            questionAvTags = []
            answerAvTags = []
            currentAvTags = []
        }
    }

    func answerCard(
        cardId: Int64,
        rating: Anki_Scheduler_CardAnswer.Rating,
        currentState: Anki_Scheduler_SchedulingState,
        newState: Anki_Scheduler_SchedulingState,
        timeLimitSecs: UInt32 = 0
    ) async {
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let elapsedMilliseconds = elapsedSeconds * 1000
            let cappedMilliseconds: Int = if timeLimitSecs > 0 {
                min(elapsedMilliseconds, Int(timeLimitSecs) * 1000)
            } else {
                elapsedMilliseconds
            }
            _ = try await service.answerCard(
                cardId: cardId,
                rating: rating,
                currentState: currentState,
                newState: newState,
                answeredAtMillis: now,
                millisecondsTaken: UInt32(cappedMilliseconds)
            )
            stopTimer()
            await loadQueue()
            await refreshUndoStatus()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func undoLastAnswer() async {
        do {
            _ = try await service.undo()
            await loadQueue()
            await refreshUndoStatus()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    var currentFlag: UInt32 {
        queuedCards?.cards.first?.card.flags ?? 0
    }

    func buryCard() async {
        guard let cardId = queuedCards?.cards.first?.card.id else { return }
        do {
            _ = try await service.buryOrSuspendCards(cardIds: [cardId], noteIds: [], mode: .buryUser)
            await loadQueue()
            await refreshUndoStatus()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func buryNote() async {
        guard let noteId = queuedCards?.cards.first?.card.noteID else { return }
        do {
            _ = try await service.buryOrSuspendCards(cardIds: [], noteIds: [noteId], mode: .buryUser)
            await loadQueue()
            await refreshUndoStatus()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func suspendCard() async {
        guard let cardId = queuedCards?.cards.first?.card.id else { return }
        do {
            _ = try await service.buryOrSuspendCards(cardIds: [cardId], noteIds: [], mode: .suspend)
            await loadQueue()
            await refreshUndoStatus()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func flagCard(flag: UInt32) async {
        guard let cardId = queuedCards?.cards.first?.card.id else { return }
        do {
            _ = try await service.setFlag(cardIds: [cardId], flag: flag)
            await loadQueue()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    private func refreshUndoStatus() async {
        do {
            let status = try await service.getUndoStatus()
            undoLabel = status.undo.isEmpty ? nil : status.undo
        } catch {
            undoLabel = nil
        }
    }

    func intervalLabel(for rating: Anki_Scheduler_CardAnswer.Rating) -> String? {
        guard let states = queuedCards?.cards.first?.states else { return nil }

        let state: Anki_Scheduler_SchedulingState = switch rating {
            case .again: states.again
            case .hard: states.hard
            case .good: states.good
            case .easy: states.easy
            case .UNRECOGNIZED: states.good
        }

        return formattedInterval(for: state)
    }

    private func formattedInterval(for state: Anki_Scheduler_SchedulingState) -> String? {
        switch state.kind {
            case let .normal(normal):
                formattedInterval(for: normal)
            case let .filtered(filtered):
                formattedInterval(for: filtered)
            case .none:
                nil
        }
    }

    private func formattedInterval(for normal: Anki_Scheduler_SchedulingState.Normal) -> String? {
        switch normal.kind {
            case .new:
                return nil
            case let .learning(learning):
                return formattedSeconds(learning.scheduledSecs)
            case let .review(review):
                return formattedDays(review.scheduledDays)
            case let .relearning(relearning):
                if relearning.hasLearning {
                    return formattedSeconds(relearning.learning.scheduledSecs)
                }
                if relearning.hasReview {
                    return formattedDays(relearning.review.scheduledDays)
                }
                return nil
            case .none:
                return nil
        }
    }

    private func formattedInterval(for filtered: Anki_Scheduler_SchedulingState.Filtered) -> String? {
        switch filtered.kind {
            case let .preview(preview):
                formattedSeconds(preview.scheduledSecs)
            case let .rescheduling(rescheduling):
                formattedInterval(for: rescheduling.originalState)
            case .none:
                nil
        }
    }

    private func formattedSeconds(_ seconds: UInt32) -> String {
        let seconds = Int(seconds)
        if seconds < 60 {
            return "\(max(1, seconds))s"
        }
        if seconds < 3600 {
            return "\(Int((Double(seconds) / 60).rounded()))m"
        }
        if seconds < 86400 {
            return "\(Int((Double(seconds) / 3600).rounded()))h"
        }
        return "\(Int((Double(seconds) / 86400).rounded()))d"
    }

    private func formattedDays(_ days: UInt32) -> String {
        let days = Int(days)
        if days == 0 {
            return "<1d"
        }
        if days < 30 {
            return "\(days)d"
        }
        if days < 365 {
            return "\(Int((Double(days) / 30).rounded()))mo"
        }
        return "\(Int((Double(days) / 365).rounded()))y"
    }
}

private extension Anki_CardRendering_RenderedTemplateNode {
    var replacementIfPresent: Anki_CardRendering_RenderedTemplateReplacement? {
        switch value {
            case let .replacement(replacement):
                replacement
            default:
                nil
        }
    }
}

// swiftlint:enable file_length
