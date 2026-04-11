@testable import AnkiApp
@testable import AppleBridgeCore
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
        state.session.isCollectionOpen = true

        await state.startReview(deckId: 42)

        #expect(state.isShowingReviewer)
        #expect(await service.setCurrentDeckCalls() == [42])
    }

    @Test @MainActor
    func knowledgeGraphModelLoadsStatusAndTaxonomy() async {
        let atlas = TestAtlasService(
            statusResponses: [
                KnowledgeGraphStatus(
                    conceptEdgeCount: 12,
                    topicEdgeCount: 4,
                    lastRefreshedAt: "2026-04-10T12:00:00Z",
                    similarityAvailable: true,
                    warnings: []
                )
            ],
            taxonomyTree: [sampleTaxonomyNode()]
        )
        let model = KnowledgeGraphModel(atlas: atlas)

        await model.load()

        #expect(model.status?.conceptEdgeCount == 12)
        #expect(model.status?.topicEdgeCount == 4)
        #expect(model.taxonomyTree.count == 1)
        #expect(await atlas.statusCalls() == 1)
        #expect(await atlas.taxonomyCalls() == 1)
    }

    @Test @MainActor
    func knowledgeGraphModelSelectTopicLoadsNeighborhood() async {
        let node = sampleTaxonomyNode()
        let atlas = TestAtlasService(
            taxonomyTree: [node],
            neighborhoods: [node.topicId: sampleNeighborhoodResponse(rootTopicId: node.topicId)]
        )
        let model = KnowledgeGraphModel(atlas: atlas)

        await model.selectTopic(node)

        #expect(model.selectedTopicId == node.topicId)
        #expect(model.neighborhood?.rootTopicId == node.topicId)
        #expect(await atlas.neighborhoodCalls() == [node.topicId])
    }

    @Test @MainActor
    func knowledgeGraphModelRebuildReloadsStatusAndNeighborhood() async {
        let node = sampleTaxonomyNode()
        let atlas = TestAtlasService(
            statusResponses: [
                KnowledgeGraphStatus(
                    conceptEdgeCount: 0,
                    topicEdgeCount: 0,
                    lastRefreshedAt: nil,
                    similarityAvailable: false,
                    warnings: []
                ),
                KnowledgeGraphStatus(
                    conceptEdgeCount: 8,
                    topicEdgeCount: 6,
                    lastRefreshedAt: "2026-04-10T13:00:00Z",
                    similarityAvailable: true,
                    warnings: ["Vectors were unavailable for some notes."]
                )
            ],
            taxonomyTree: [node],
            neighborhoods: [node.topicId: sampleNeighborhoodResponse(rootTopicId: node.topicId)]
        )
        let model = KnowledgeGraphModel(atlas: atlas)

        await model.load()
        await model.selectTopic(node)
        await model.rebuild()

        #expect(model.status?.conceptEdgeCount == 8)
        #expect(model.status?.topicEdgeCount == 6)
        #expect(await atlas.refreshCalls() == 1)
        #expect(await atlas.neighborhoodCalls() == [node.topicId, node.topicId])
    }

    @Test @MainActor
    func noteLinksModelLoadsRelatedNotes() async {
        let related = NoteLink(
            noteId: 99,
            weight: 0.84,
            edgeType: .related,
            edgeSource: .tagCooccurrence,
            textPreview: "Related note preview",
            deckNames: ["Default"],
            tags: ["swift"]
        )
        let atlas = TestAtlasService(noteLinks: [42: [related]])
        let model = NoteLinksModel(atlas: atlas)

        await model.load(noteId: 42)

        #expect(model.relatedNotes.count == 1)
        #expect(model.relatedNotes.first?.noteId == 99)
        #expect(await atlas.noteLinkCalls() == [42])
    }
}
