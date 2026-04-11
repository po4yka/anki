@testable import AppleBridgeCore
import Testing

struct CompareAnswerCall: Equatable, Sendable {
    let expected: String
    let provided: String
    let combining: Bool
}

struct RemoveNotesCall: Equatable, Sendable {
    let noteIds: [Int64]
    let cardIds: [Int64]
}

struct SetDueDateCall: Equatable, Sendable {
    let cardIds: [Int64]
    let days: String
}

struct AddNoteTagsCall: Equatable, Sendable {
    let noteIds: [Int64]
    let tags: String
}

actor TestAnkiService: AnkiServiceProtocol {
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

actor TestAtlasService: AtlasServiceProtocol {
    private var remainingStatuses: [KnowledgeGraphStatus]
    private let taxonomyTreeValue: [TaxonomyNode]
    private let noteLinksByNoteId: [Int64: [NoteLink]]
    private let neighborhoodsByTopicId: [Int64: TopicNeighborhoodResponse]
    private let refreshValue: RefreshKnowledgeGraphResponse

    private var statusCallCount = 0
    private var taxonomyCallCount = 0
    private var refreshCallCount = 0
    private var requestedNoteIds: [Int64] = []
    private var requestedTopicIds: [Int64] = []

    init(
        statusResponses: [KnowledgeGraphStatus] = [KnowledgeGraphStatus(
            conceptEdgeCount: 0,
            topicEdgeCount: 0,
            lastRefreshedAt: nil,
            similarityAvailable: false,
            warnings: []
        )],
        taxonomyTree: [TaxonomyNode] = [],
        noteLinks: [Int64: [NoteLink]] = [:],
        neighborhoods: [Int64: TopicNeighborhoodResponse] = [:],
        refreshValue: RefreshKnowledgeGraphResponse = RefreshKnowledgeGraphResponse(
            conceptTagEdgesWritten: 0,
            conceptSimilarityEdgesWritten: 0,
            topicSpecializationEdgesWritten: 0,
            topicCooccurrenceEdgesWritten: 0,
            conceptEdgeCount: 0,
            topicEdgeCount: 0,
            warnings: []
        )
    ) {
        self.remainingStatuses = statusResponses
        self.taxonomyTreeValue = taxonomyTree
        self.noteLinksByNoteId = noteLinks
        self.neighborhoodsByTopicId = neighborhoods
        self.refreshValue = refreshValue
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        SearchResponse(
            query: request.query,
            results: [],
            stats: FusionStats(semanticOnly: 0, ftsOnly: 0, both: 0, total: 0),
            lexicalFallbackUsed: false,
            querySuggestions: [],
            autocompleteSuggestions: [],
            rerankApplied: false,
            rerankModel: nil,
            rerankTopN: nil
        )
    }

    func searchChunks(_ request: ChunkSearchRequest) async throws -> ChunkSearchResponse {
        ChunkSearchResponse(query: request.query, results: [])
    }

    func generatePreview(filePath: String) async throws -> GeneratePreview {
        GeneratePreview(cards: [], topic: nil)
    }

    func generatePreviewFromText(_ request: GeneratePreviewRequest) async throws -> GeneratePreview {
        GeneratePreview(cards: [], topic: request.topic)
    }

    func getTaxonomyTree(rootPath: String?) async throws -> [TaxonomyNode] {
        taxonomyCallCount += 1
        return taxonomyTreeValue
    }

    func getCoverage(topicPath: String, includeSubtree: Bool) async throws -> TopicCoverage? {
        nil
    }

    func getGaps(topicPath: String, minCoverage: Int) async throws -> [TopicGap] {
        []
    }

    func getWeakNotes(topicPath: String) async throws -> [WeakNote] {
        []
    }

    func findDuplicates(threshold: Double) async throws -> FindDuplicatesResponse {
        FindDuplicatesResponse(clusters: [], stats: DuplicateStats(totalNotes: 0, clustersFound: 0, duplicateNotes: 0))
    }

    func kgStatus() async throws -> KnowledgeGraphStatus {
        statusCallCount += 1
        if remainingStatuses.count > 1 {
            return remainingStatuses.removeFirst()
        }
        return remainingStatuses.first ?? KnowledgeGraphStatus(
            conceptEdgeCount: 0,
            topicEdgeCount: 0,
            lastRefreshedAt: nil,
            similarityAvailable: false,
            warnings: []
        )
    }

    func refreshKnowledgeGraph(_ request: RefreshKnowledgeGraphRequest) async throws -> RefreshKnowledgeGraphResponse {
        refreshCallCount += 1
        return refreshValue
    }

    func getNoteLinks(noteId: Int64, limit: Int) async throws -> NoteLinksResponse {
        requestedNoteIds.append(noteId)
        return NoteLinksResponse(
            focusNoteId: noteId,
            relatedNotes: noteLinksByNoteId[noteId] ?? []
        )
    }

    func getTopicNeighborhood(topicId: Int64, maxHops: Int, limitPerHop: Int) async throws -> TopicNeighborhoodResponse {
        requestedTopicIds.append(topicId)
        return neighborhoodsByTopicId[topicId] ?? TopicNeighborhoodResponse(
            rootTopicId: topicId,
            topics: [],
            edges: []
        )
    }

    func obsidianScan(_ request: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        ObsidianScanPreview(totalNotes: 0, notes: [])
    }

    func statusCalls() -> Int {
        statusCallCount
    }

    func taxonomyCalls() -> Int {
        taxonomyCallCount
    }

    func refreshCalls() -> Int {
        refreshCallCount
    }

    func noteLinkCalls() -> [Int64] {
        requestedNoteIds
    }

    func neighborhoodCalls() -> [Int64] {
        requestedTopicIds
    }
}

func makeQueuedCards(cardId: Int64, noteId: Int64, deckId: Int64, templateIdx: UInt32) -> Anki_Scheduler_QueuedCards {
    let card = makeCard(id: cardId, noteId: noteId, deckId: deckId, templateIdx: templateIdx)
    var queuedCard = Anki_Scheduler_QueuedCards.QueuedCard()
    queuedCard.card = card

    var queuedCards = Anki_Scheduler_QueuedCards()
    queuedCards.cards = [queuedCard]
    return queuedCards
}

func makeCard(id: Int64, noteId: Int64, deckId: Int64 = 1, templateIdx: UInt32 = 0) -> Anki_Cards_Card {
    var card = Anki_Cards_Card()
    card.id = id
    card.noteID = noteId
    card.deckID = deckId
    card.templateIdx = templateIdx
    return card
}

func makeRenderedCard(
    questionNodes: [Anki_CardRendering_RenderedTemplateNode],
    answerNodes: [Anki_CardRendering_RenderedTemplateNode]
) -> Anki_CardRendering_RenderCardResponse {
    var response = Anki_CardRendering_RenderCardResponse()
    response.questionNodes = questionNodes
    response.answerNodes = answerNodes
    return response
}

func textNode(_ text: String) -> Anki_CardRendering_RenderedTemplateNode {
    var node = Anki_CardRendering_RenderedTemplateNode()
    node.text = text
    return node
}

func replacementNode(fieldName: String, currentText: String) -> Anki_CardRendering_RenderedTemplateNode {
    var replacement = Anki_CardRendering_RenderedTemplateReplacement()
    replacement.fieldName = fieldName
    replacement.currentText = currentText

    var node = Anki_CardRendering_RenderedTemplateNode()
    node.replacement = replacement
    return node
}

func sampleTaxonomyNode() -> TaxonomyNode {
    TaxonomyNode(
        topicId: 1,
        path: "rust/ownership",
        label: "Ownership",
        noteCount: 3,
        children: []
    )
}

func sampleNeighborhoodResponse(rootTopicId: Int64) -> TopicNeighborhoodResponse {
    TopicNeighborhoodResponse(
        rootTopicId: rootTopicId,
        topics: [
            TopicNodeSummary(topicId: rootTopicId, path: "rust/ownership", label: "Ownership", noteCount: 3),
            TopicNodeSummary(topicId: 2, path: "rust/borrowing", label: "Borrowing", noteCount: 2)
        ],
        edges: [
            TopicEdgeView(
                sourceTopicId: rootTopicId,
                targetTopicId: 2,
                edgeType: .related,
                edgeSource: .topicCooccurrence,
                weight: 0.66
            )
        ]
    )
}
