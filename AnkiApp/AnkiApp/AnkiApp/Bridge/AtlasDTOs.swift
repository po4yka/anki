import Foundation

// MARK: - Search

enum SearchMode: String, Codable {
    case hybrid
    case semanticOnly = "semantic_only"
    case ftsOnly = "fts_only"
}

struct SearchFilterInput: Codable {
    var deckNames: [String]?
    var deckNamesExclude: [String]?
    var tags: [String]?
    var tagsExclude: [String]?
    var modelIds: [Int64]?
    var minIvl: Int32?
    var maxLapses: Int32?
    var minReps: Int32?

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
}

struct SearchRequest: Codable {
    var query: String
    var filters: SearchFilterInput?
    var limit: Int = 50
    var semanticWeight: Double = 1.0
    var ftsWeight: Double = 1.0
    var searchMode: SearchMode = .hybrid
    var rerankOverride: Bool?
    var rerankTopNOverride: Int?

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
}

struct FusionStats: Codable {
    var semanticOnly: Int
    var ftsOnly: Int
    var both: Int
    var total: Int

    enum CodingKeys: String, CodingKey {
        case semanticOnly = "semantic_only"
        case ftsOnly = "fts_only"
        case both
        case total
    }
}

struct SearchResultItem: Codable, Identifiable {
    var noteId: Int64
    var rrfScore: Double
    var semanticScore: Double?
    var semanticRank: Int?
    var ftsScore: Double?
    var ftsRank: Int?
    var headline: String?
    var rerankScore: Double?
    var rerankRank: Int?
    var sources: [String]
    var matchModality: String?
    var matchChunkKind: String?
    var matchSourceField: String?
    var matchAssetRelPath: String?
    var matchPreviewLabel: String?

    var id: Int64 {
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

struct SearchResponse: Codable {
    var query: String
    var results: [SearchResultItem]
    var stats: FusionStats
    var lexicalFallbackUsed: Bool
    var querySuggestions: [String]
    var autocompleteSuggestions: [String]
    var rerankApplied: Bool
    var rerankModel: String?
    var rerankTopN: Int?

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

struct TopicCoverage: Codable {
    var topicId: Int64
    var path: String
    var label: String
    var noteCount: Int64
    var subtreeCount: Int64
    var childCount: Int64
    var coveredChildren: Int64
    var matureCount: Int64
    var avgConfidence: Double
    var weakNotes: Int64
    var avgLapses: Double

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

enum GapKind: String, Codable {
    case missing
    case undercovered
}

struct TopicGap: Codable, Identifiable {
    var topicId: Int64
    var path: String
    var label: String
    var description: String?
    var gapType: GapKind
    var noteCount: Int64
    var threshold: Int64

    var id: Int64 {
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

struct WeakNote: Codable, Identifiable {
    var noteId: Int64
    var topicPath: String
    var confidence: Double
    var lapses: Int32
    var failRate: Double?
    var normalizedText: String

    var id: Int64 {
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

struct TaxonomyNode: Codable, Identifiable {
    var topicId: Int64
    var path: String
    var label: String
    var noteCount: Int
    var children: [TaxonomyNode]

    var id: Int64 {
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

struct ObsidianScanRequest: Codable {
    var vaultPath: String

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
    }
}

struct ObsidianNotePreview: Codable, Identifiable {
    var path: String
    var title: String
    var sectionCount: Int
    var generatedCardCount: Int

    var id: String {
        path
    }

    enum CodingKeys: String, CodingKey {
        case path
        case title
        case sectionCount = "section_count"
        case generatedCardCount = "generated_card_count"
    }
}

struct ObsidianScanPreview: Codable {
    var totalNotes: Int
    var notes: [ObsidianNotePreview]

    enum CodingKeys: String, CodingKey {
        case totalNotes = "total_notes"
        case notes
    }
}

// MARK: - Chunk Search

struct ChunkSearchRequest: Codable {
    var query: String
    var limit: Int = 20
    var filters: SearchFilterInput?
}

struct ChunkSearchResult: Codable, Identifiable {
    var chunkId: Int64
    var noteId: Int64
    var score: Double
    var text: String
    var chunkKind: String?
    var sourceField: String?

    var id: Int64 {
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

struct ChunkSearchResponse: Codable {
    var query: String
    var results: [ChunkSearchResult]
}

// MARK: - Shared Request Helpers

struct EmptyRequest: Encodable {}

struct TopicPathRequest: Encodable {
    let topicPath: String
    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
    }
}

struct GapsRequest: Encodable {
    let topicPath: String
    let minCoverage: Int
    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
        case minCoverage = "min_coverage"
    }
}

struct DuplicatesRequest: Encodable {
    let threshold: Double
}

struct FindDuplicatesResponse: Decodable {
    let clusters: [DuplicateCluster]
    let stats: DuplicateStats
}

struct DuplicateStats: Codable {
    var totalNotes: Int
    var clustersFound: Int
    var duplicateNotes: Int

    enum CodingKeys: String, CodingKey {
        case totalNotes = "total_notes"
        case clustersFound = "clusters_found"
        case duplicateNotes = "duplicate_notes"
    }
}

// MARK: - Card Generator

struct GeneratePreviewRequest: Codable {
    var sourceText: String
    var topic: String?

    enum CodingKeys: String, CodingKey {
        case sourceText = "source_text"
        case topic
    }
}

struct GeneratePreviewFromFileRequest: Encodable {
    var filePath: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}

struct PreviewCard: Codable, Identifiable {
    var front: String
    var back: String
    var cardType: String
    var confidence: Double?

    var id: String {
        front
    }

    enum CodingKeys: String, CodingKey {
        case front
        case back
        case cardType = "card_type"
        case confidence
    }
}

struct GeneratePreview: Codable {
    var cards: [PreviewCard]
    var topic: String?

    enum CodingKeys: String, CodingKey {
        case cards
        case topic
    }
}
