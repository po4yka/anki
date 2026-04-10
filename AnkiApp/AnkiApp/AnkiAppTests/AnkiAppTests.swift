@testable import AnkiApp
import Testing

struct AnkiAppTests {
    @Test func parsesFieldTypeAnswer() {
        let spec = TypeAnswerSpec.parse(questionHTML: "<div>[[type:Front]]</div>")

        #expect(spec == TypeAnswerSpec(kind: .field(combining: true), fieldName: "Front"))
    }

    @Test func parsesNonCombiningFieldTypeAnswer() {
        let spec = TypeAnswerSpec.parse(questionHTML: "[[type:nc:Back]]")

        #expect(spec == TypeAnswerSpec(kind: .field(combining: false), fieldName: "Back"))
    }

    @Test func parsesClozeTypeAnswer() {
        let spec = TypeAnswerSpec.parse(questionHTML: "<span>[[type:cloze:Text]]</span>")

        #expect(spec == TypeAnswerSpec(kind: .cloze, fieldName: "Text"))
    }

    @Test func ignoresCardsWithoutTypeAnswerMarker() {
        #expect(TypeAnswerSpec.parse(questionHTML: "<div>Front</div>") == nil)
    }

    @Test @MainActor
    func reviewerComparesNonCombiningFieldAgainstRenderedAnswerText() async {
        let service = TestAnkiService(
            queuedCardsResponse: makeQueuedCards(cardId: 11, noteId: 42, deckId: 7, templateIdx: 0),
            renderExistingCardResponse: makeRenderedCard(
                questionNodes: [textNode("[[type:nc:Back]]")],
                answerNodes: [replacementNode(fieldName: "Back", currentText: "Expected Kana")]
            ),
            compareAnswerResponse: "<div>diff</div>"
        )
        let model = ReviewerModel(service: service)

        await model.loadQueue()
        model.typedAnswer = "Provided"
        await model.compareTypedAnswer()

        let compareCall = await service.lastCompareAnswerCall()
        #expect(compareCall == CompareAnswerCall(expected: "Expected Kana", provided: "Provided", combining: false))
        #expect(model.comparisonHTML == "<div>diff</div>")
    }

    @Test @MainActor
    func reviewerExtractsClozeTextForCurrentTemplateOrdinal() async {
        let service = TestAnkiService(
            queuedCardsResponse: makeQueuedCards(cardId: 21, noteId: 84, deckId: 9, templateIdx: 1),
            renderExistingCardResponse: makeRenderedCard(
                questionNodes: [textNode("[[type:cloze:Text]]")],
                answerNodes: [
                    replacementNode(
                        fieldName: "Text",
                        currentText: "One {{c2::second}} and another {{c2::other}} plus {{c1::ignored}}"
                    )
                ]
            ),
            compareAnswerResponse: "<div>cloze</div>"
        )
        let model = ReviewerModel(service: service)

        await model.loadQueue()
        model.typedAnswer = "Provided"
        await model.compareTypedAnswer()

        let compareCall = await service.lastCompareAnswerCall()
        #expect(compareCall == CompareAnswerCall(expected: "second, other", provided: "Provided", combining: true))
        #expect(model.comparisonHTML == "<div>cloze</div>")
    }

    @Test @MainActor
    func notesModeDeletesUsingNoteIDs() async {
        let service = TestAnkiService()
        let model = SearchModel(service: service)
        model.searchMode = .notes
        model.selectedResultIds = [10, 20]

        await model.deleteSelected()

        let call = await service.lastRemoveNotesCall()
        #expect(Set(call?.noteIds ?? []) == Set<Int64>([10, 20]))
        #expect(call?.cardIds.isEmpty == true)
    }

    @Test @MainActor
    func notesModeConvertsSelectedNotesToCardIDsForDueDateActions() async {
        let service = TestAnkiService(cardsOfNoteResponses: [
            10: [100, 101],
            20: [200]
        ])
        let model = SearchModel(service: service)
        model.searchMode = .notes
        model.selectedResultIds = [10, 20]

        await model.setDueDateForSelected(days: "5")

        let call = await service.lastSetDueDateCall()
        #expect(Set(call?.cardIds ?? []) == Set<Int64>([100, 101, 200]))
        #expect(call?.days == "5")
    }

    @Test @MainActor
    func cardModeTagOperationsDeduplicateMappedNoteIDs() async {
        let service = TestAnkiService(getCardResponses: [
            1: makeCard(id: 1, noteId: 7),
            2: makeCard(id: 2, noteId: 7),
            3: makeCard(id: 3, noteId: 8)
        ])
        let model = SearchModel(service: service)
        model.searchMode = .cards
        model.selectedResultIds = [1, 2, 3]

        await model.addTagsToSelected(tags: "important")

        let call = await service.lastAddNoteTagsCall()
        #expect(Set(call?.noteIds ?? []) == Set<Int64>([7, 8]))
        #expect(call?.tags == "important")
    }

    @Test @MainActor
    func appStateRequiresAnOpenCollectionBeforePresentingAddNote() {
        let state = AppState(service: TestAnkiService())

        state.presentAddNote()

        #expect(state.isShowingAddNote == false)
        #expect(state.error?.errorDescription == "Open a collection before adding notes.")
    }

    @Test @MainActor
    func appStateStartsDeckScopedReviewWhenCollectionIsOpen() async {
        let service = TestAnkiService()
        let state = AppState(service: service)
        state.isCollectionOpen = true

        await state.startReview(deckId: 42)

        #expect(state.isShowingReviewer)
        #expect(await service.setCurrentDeckCalls() == [42])
    }
}

private struct CompareAnswerCall: Equatable, Sendable {
    let expected: String
    let provided: String
    let combining: Bool
}

private struct RemoveNotesCall: Equatable, Sendable {
    let noteIds: [Int64]
    let cardIds: [Int64]
}

private struct SetDueDateCall: Equatable, Sendable {
    let cardIds: [Int64]
    let days: String
}

private struct AddNoteTagsCall: Equatable, Sendable {
    let noteIds: [Int64]
    let tags: String
}

private actor TestAnkiService: AnkiServiceProtocol {
    private let queuedCardsResponse: Anki_Scheduler_QueuedCards
    private let renderExistingCardResponse: Anki_CardRendering_RenderCardResponse
    private let compareAnswerResponse: String
    private let getCardResponses: [Int64: Anki_Cards_Card]
    private let cardsOfNoteResponses: [Int64: [Int64]]

    private var compareAnswerCalls: [CompareAnswerCall] = []
    private var removeNotesCalls: [RemoveNotesCall] = []
    private var setDueDateCalls: [SetDueDateCall] = []
    private var addNoteTagsCalls: [AddNoteTagsCall] = []
    private var currentDeckCalls: [Int64] = []

    init(
        queuedCardsResponse: Anki_Scheduler_QueuedCards = Anki_Scheduler_QueuedCards(),
        renderExistingCardResponse: Anki_CardRendering_RenderCardResponse = Anki_CardRendering_RenderCardResponse(),
        compareAnswerResponse: String = "",
        getCardResponses: [Int64: Anki_Cards_Card] = [:],
        cardsOfNoteResponses: [Int64: [Int64]] = [:]
    ) {
        self.queuedCardsResponse = queuedCardsResponse
        self.renderExistingCardResponse = renderExistingCardResponse
        self.compareAnswerResponse = compareAnswerResponse
        self.getCardResponses = getCardResponses
        self.cardsOfNoteResponses = cardsOfNoteResponses
    }

    func getQueuedCards(fetchLimit: UInt32) async throws -> Anki_Scheduler_QueuedCards {
        queuedCardsResponse
    }

    func renderExistingCard(cardId: Int64) async throws -> Anki_CardRendering_RenderCardResponse {
        renderExistingCardResponse
    }

    func compareAnswer(expected: String, provided: String, combining: Bool) async throws -> String {
        compareAnswerCalls.append(CompareAnswerCall(expected: expected, provided: provided, combining: combining))
        return compareAnswerResponse
    }

    func removeNotes(noteIds: [Int64], cardIds: [Int64]) async throws -> Anki_Collection_OpChangesWithCount {
        removeNotesCalls.append(RemoveNotesCall(noteIds: noteIds, cardIds: cardIds))
        return Anki_Collection_OpChangesWithCount()
    }

    func cardsOfNote(noteId: Int64) async throws -> [Int64] {
        cardsOfNoteResponses[noteId] ?? []
    }

    func setDueDate(cardIds: [Int64], days: String) async throws -> Anki_Collection_OpChanges {
        setDueDateCalls.append(SetDueDateCall(cardIds: cardIds, days: days))
        return Anki_Collection_OpChanges()
    }

    func getCard(id: Int64) async throws -> Anki_Cards_Card {
        guard let card = getCardResponses[id] else {
            throw AnkiError.message("Missing stub card for id \(id)")
        }
        return card
    }

    func addNoteTags(noteIds: [Int64], tags: String) async throws -> Anki_Collection_OpChangesWithCount {
        addNoteTagsCalls.append(AddNoteTagsCall(noteIds: noteIds, tags: tags))
        return Anki_Collection_OpChangesWithCount()
    }

    func setCurrentDeck(deckId: Int64) async throws {
        currentDeckCalls.append(deckId)
    }

    func setBrowserTableNotesMode(_ enabled: Bool) async throws {}

    func lastCompareAnswerCall() -> CompareAnswerCall? {
        compareAnswerCalls.last
    }

    func lastRemoveNotesCall() -> RemoveNotesCall? {
        removeNotesCalls.last
    }

    func lastSetDueDateCall() -> SetDueDateCall? {
        setDueDateCalls.last
    }

    func lastAddNoteTagsCall() -> AddNoteTagsCall? {
        addNoteTagsCalls.last
    }

    func setCurrentDeckCalls() -> [Int64] {
        currentDeckCalls
    }
}

private func makeQueuedCards(cardId: Int64, noteId: Int64, deckId: Int64, templateIdx: UInt32) -> Anki_Scheduler_QueuedCards {
    let card = makeCard(id: cardId, noteId: noteId, deckId: deckId, templateIdx: templateIdx)
    var queuedCard = Anki_Scheduler_QueuedCards.QueuedCard()
    queuedCard.card = card

    var queuedCards = Anki_Scheduler_QueuedCards()
    queuedCards.cards = [queuedCard]
    return queuedCards
}

private func makeCard(id: Int64, noteId: Int64, deckId: Int64 = 1, templateIdx: UInt32 = 0) -> Anki_Cards_Card {
    var card = Anki_Cards_Card()
    card.id = id
    card.noteID = noteId
    card.deckID = deckId
    card.templateIdx = templateIdx
    return card
}

private func makeRenderedCard(
    questionNodes: [Anki_CardRendering_RenderedTemplateNode],
    answerNodes: [Anki_CardRendering_RenderedTemplateNode]
) -> Anki_CardRendering_RenderCardResponse {
    var response = Anki_CardRendering_RenderCardResponse()
    response.questionNodes = questionNodes
    response.answerNodes = answerNodes
    return response
}

private func textNode(_ text: String) -> Anki_CardRendering_RenderedTemplateNode {
    var node = Anki_CardRendering_RenderedTemplateNode()
    node.text = text
    return node
}

private func replacementNode(fieldName: String, currentText: String) -> Anki_CardRendering_RenderedTemplateNode {
    var replacement = Anki_CardRendering_RenderedTemplateReplacement()
    replacement.fieldName = fieldName
    replacement.currentText = currentText

    var node = Anki_CardRendering_RenderedTemplateNode()
    node.replacement = replacement
    return node
}
