import Foundation

// MARK: - Search

public enum SearchMode: String, Codable {
    case hybrid
    case semanticOnly = "semantic_only"
    case ftsOnly = "fts_only"
}

public struct SearchFilterInput: Codable {
    public var deckNames: [String]?
    public var deckNamesExclude: [String]?
    public var tags: [String]?
    public var tagsExclude: [String]?
    public var modelIds: [Int64]?
    public var minIvl: Int32?
    public var maxLapses: Int32?
    public var minReps: Int32?

    enum CodingKeys: String, CodingKey {
        case deckNames = "deck_names"
        case deckNamesExclude = "deck_names_exclude"
        case tags
        case tagsExclude = "tags_exclude"
        case modelIds = "model_ids"
        case minIvl = "min_ivl"
        case maxLapses = "max_lapses"
        case minReps = "min_reps"
    }

    public init(
        deckNames: [String]? = nil,
        deckNamesExclude: [String]? = nil,
        tags: [String]? = nil,
        tagsExclude: [String]? = nil,
        modelIds: [Int64]? = nil,
        minIvl: Int32? = nil,
        maxLapses: Int32? = nil,
        minReps: Int32? = nil
    ) {
        self.deckNames = deckNames
        self.deckNamesExclude = deckNamesExclude
        self.tags = tags
        self.tagsExclude = tagsExclude
        self.modelIds = modelIds
        self.minIvl = minIvl
        self.maxLapses = maxLapses
        self.minReps = minReps
    }
}

public struct SearchRequest: Codable {
    public var query: String
    public var filters: SearchFilterInput?
    public var limit: Int = 50
    public var semanticWeight: Double = 1.0
    public var ftsWeight: Double = 1.0
    public var searchMode: SearchMode = .hybrid
    public var rerankOverride: Bool?
    public var rerankTopNOverride: Int?

    enum CodingKeys: String, CodingKey {
        case query
        case filters
        case limit
        case semanticWeight = "semantic_weight"
        case ftsWeight = "fts_weight"
        case searchMode = "search_mode"
        case rerankOverride = "rerank_override"
        case rerankTopNOverride = "rerank_top_n_override"
    }

    public init(
        query: String,
        filters: SearchFilterInput? = nil,
        limit: Int = 50,
        semanticWeight: Double = 1.0,
        ftsWeight: Double = 1.0,
        searchMode: SearchMode = .hybrid,
        rerankOverride: Bool? = nil,
        rerankTopNOverride: Int? = nil
    ) {
        self.query = query
        self.filters = filters
        self.limit = limit
        self.semanticWeight = semanticWeight
        self.ftsWeight = ftsWeight
        self.searchMode = searchMode
        self.rerankOverride = rerankOverride
        self.rerankTopNOverride = rerankTopNOverride
    }
}

public struct FusionStats: Codable {
    public var semanticOnly: Int
    public var ftsOnly: Int
    public var both: Int
    public var total: Int

    enum CodingKeys: String, CodingKey {
        case semanticOnly = "semantic_only"
        case ftsOnly = "fts_only"
        case both
        case total
    }
}

public struct SearchResultItem: Codable, Identifiable {
    public var noteId: Int64
    public var rrfScore: Double
    public var semanticScore: Double?
    public var semanticRank: Int?
    public var ftsScore: Double?
    public var ftsRank: Int?
    public var headline: String?
    public var rerankScore: Double?
    public var rerankRank: Int?
    public var sources: [String]
    public var matchModality: String?
    public var matchChunkKind: String?
    public var matchSourceField: String?
    public var matchAssetRelPath: String?
    public var matchPreviewLabel: String?

    public var id: Int64 {
        noteId
    }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case rrfScore = "rrf_score"
        case semanticScore = "semantic_score"
        case semanticRank = "semantic_rank"
        case ftsScore = "fts_score"
        case ftsRank = "fts_rank"
        case headline
        case rerankScore = "rerank_score"
        case rerankRank = "rerank_rank"
        case sources
        case matchModality = "match_modality"
        case matchChunkKind = "match_chunk_kind"
        case matchSourceField = "match_source_field"
        case matchAssetRelPath = "match_asset_rel_path"
        case matchPreviewLabel = "match_preview_label"
    }
}

public struct SearchResponse: Codable {
    public var query: String
    public var results: [SearchResultItem]
    public var stats: FusionStats
    public var lexicalFallbackUsed: Bool
    public var querySuggestions: [String]
    public var autocompleteSuggestions: [String]
    public var rerankApplied: Bool
    public var rerankModel: String?
    public var rerankTopN: Int?

    enum CodingKeys: String, CodingKey {
        case query
        case results
        case stats
        case lexicalFallbackUsed = "lexical_fallback_used"
        case querySuggestions = "query_suggestions"
        case autocompleteSuggestions = "autocomplete_suggestions"
        case rerankApplied = "rerank_applied"
        case rerankModel = "rerank_model"
        case rerankTopN = "rerank_top_n"
    }
}

// MARK: - Analytics

public struct TopicCoverage: Codable {
    public var topicId: Int64
    public var path: String
    public var label: String
    public var noteCount: Int64
    public var subtreeCount: Int64
    public var childCount: Int64
    public var coveredChildren: Int64
    public var matureCount: Int64
    public var avgConfidence: Double
    public var weakNotes: Int64
    public var avgLapses: Double

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case path
        case label
        case noteCount = "note_count"
        case subtreeCount = "subtree_count"
        case childCount = "child_count"
        case coveredChildren = "covered_children"
        case matureCount = "mature_count"
        case avgConfidence = "avg_confidence"
        case weakNotes = "weak_notes"
        case avgLapses = "avg_lapses"
    }
}

public enum GapKind: String, Codable {
    case missing
    case undercovered
}

public struct TopicGap: Codable, Identifiable {
    public var topicId: Int64
    public var path: String
    public var label: String
    public var description: String?
    public var gapType: GapKind
    public var noteCount: Int64
    public var threshold: Int64

    public var id: Int64 {
        topicId
    }

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case path
        case label
        case description
        case gapType = "gap_type"
        case noteCount = "note_count"
        case threshold
    }
}

public struct WeakNote: Codable, Identifiable {
    public var noteId: Int64
    public var topicPath: String
    public var confidence: Double
    public var lapses: Int32
    public var failRate: Double?
    public var normalizedText: String

    public var id: Int64 {
        noteId
    }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case topicPath = "topic_path"
        case confidence
        case lapses
        case failRate = "fail_rate"
        case normalizedText = "normalized_text"
    }
}

// MARK: - Taxonomy

public struct TaxonomyNode: Codable, Identifiable {
    public var topicId: Int64
    public var path: String
    public var label: String
    public var noteCount: Int
    public var children: [TaxonomyNode]

    public var id: Int64 {
        topicId
    }

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case path
        case label
        case noteCount = "note_count"
        case children
    }
}

// MARK: - Obsidian

public struct ObsidianScanRequest: Codable {
    public var vaultPath: String

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
    }

    public init(vaultPath: String) {
        self.vaultPath = vaultPath
    }
}

public struct ObsidianNotePreview: Codable, Identifiable {
    public var path: String
    public var title: String
    public var sectionCount: Int
    public var generatedCardCount: Int

    public var id: String {
        path
    }

    enum CodingKeys: String, CodingKey {
        case path
        case title
        case sectionCount = "section_count"
        case generatedCardCount = "generated_card_count"
    }
}

public struct ObsidianScanPreview: Codable {
    public var totalNotes: Int
    public var notes: [ObsidianNotePreview]

    enum CodingKeys: String, CodingKey {
        case totalNotes = "total_notes"
        case notes
    }
}

// MARK: - Chunk Search

public struct ChunkSearchRequest: Codable {
    public var query: String
    public var limit: Int = 20
    public var filters: SearchFilterInput?
}

public struct ChunkSearchResult: Codable, Identifiable {
    public var chunkId: Int64
    public var noteId: Int64
    public var score: Double
    public var text: String
    public var chunkKind: String?
    public var sourceField: String?

    public var id: Int64 {
        chunkId
    }

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case noteId = "note_id"
        case score
        case text
        case chunkKind = "chunk_kind"
        case sourceField = "source_field"
    }
}

public struct ChunkSearchResponse: Codable {
    public var query: String
    public var results: [ChunkSearchResult]
}

// MARK: - Shared Request Helpers

public struct EmptyRequest: Encodable {}

public struct TopicPathRequest: Encodable {
    public let topicPath: String
    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
    }
}

public struct GapsRequest: Encodable {
    public let topicPath: String
    public let minCoverage: Int
    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
        case minCoverage = "min_coverage"
    }
}

public struct DuplicatesRequest: Encodable {
    public let threshold: Double
}

public struct FindDuplicatesResponse: Decodable {
    public let clusters: [DuplicateCluster]
    public let stats: DuplicateStats
}

public struct DuplicateStats: Codable {
    public var totalNotes: Int
    public var clustersFound: Int
    public var duplicateNotes: Int

    enum CodingKeys: String, CodingKey {
        case totalNotes = "total_notes"
        case clustersFound = "clusters_found"
        case duplicateNotes = "duplicate_notes"
    }
}

// MARK: - Card Generator

public struct GeneratePreviewRequest: Codable {
    public var sourceText: String
    public var topic: String?

    enum CodingKeys: String, CodingKey {
        case sourceText = "source_text"
        case topic
    }

    public init(sourceText: String, topic: String? = nil) {
        self.sourceText = sourceText
        self.topic = topic
    }
}

public struct GeneratePreviewFromFileRequest: Encodable {
    public var filePath: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }

    public init(filePath: String) {
        self.filePath = filePath
    }
}

public struct PreviewCard: Codable, Identifiable {
    public var front: String
    public var back: String
    public var cardType: String
    public var confidence: Double?

    public var id: String {
        front
    }

    enum CodingKeys: String, CodingKey {
        case front
        case back
        case cardType = "card_type"
        case confidence
    }
}

public struct GeneratePreview: Codable {
    public var cards: [PreviewCard]
    public var topic: String?

    enum CodingKeys: String, CodingKey {
        case cards
        case topic
    }
}
