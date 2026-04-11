import Foundation

// MARK: - Knowledge Graph

enum KnowledgeGraphEdgeType: String, Codable {
    case similar
    case prerequisite
    case related
    case crossReference = "cross_reference"
    case specialization
}

enum KnowledgeGraphEdgeSource: String, Codable {
    case embedding
    case tagCooccurrence = "tag_cooccurrence"
    case reviewInference = "review_inference"
    case wikilink
    case taxonomy
    case topicCooccurrence = "topic_cooccurrence"
    case manual
}

struct KnowledgeGraphStatus: Codable {
    var conceptEdgeCount: Int
    var topicEdgeCount: Int
    var lastRefreshedAt: String?
    var similarityAvailable: Bool
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case conceptEdgeCount = "concept_edge_count"
        case topicEdgeCount = "topic_edge_count"
        case lastRefreshedAt = "last_refreshed_at"
        case similarityAvailable = "similarity_available"
        case warnings
    }
}

struct RefreshKnowledgeGraphRequest: Codable {
    var rebuildConceptEdges: Bool = true
    var rebuildTopicEdges: Bool = true
    var noteSimilarityLimit: Int = 10

    enum CodingKeys: String, CodingKey {
        case rebuildConceptEdges = "rebuild_concept_edges"
        case rebuildTopicEdges = "rebuild_topic_edges"
        case noteSimilarityLimit = "note_similarity_limit"
    }
}

struct RefreshKnowledgeGraphResponse: Codable {
    var conceptTagEdgesWritten: Int
    var conceptSimilarityEdgesWritten: Int
    var topicSpecializationEdgesWritten: Int
    var topicCooccurrenceEdgesWritten: Int
    var conceptEdgeCount: Int
    var topicEdgeCount: Int
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case conceptTagEdgesWritten = "concept_tag_edges_written"
        case conceptSimilarityEdgesWritten = "concept_similarity_edges_written"
        case topicSpecializationEdgesWritten = "topic_specialization_edges_written"
        case topicCooccurrenceEdgesWritten = "topic_cooccurrence_edges_written"
        case conceptEdgeCount = "concept_edge_count"
        case topicEdgeCount = "topic_edge_count"
        case warnings
    }
}

struct NoteLinksRequest: Codable {
    var noteId: Int64
    var limit: Int = 12

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case limit
    }
}

struct NoteLink: Codable, Identifiable {
    var noteId: Int64
    var weight: Float
    var edgeType: KnowledgeGraphEdgeType
    var edgeSource: KnowledgeGraphEdgeSource
    var textPreview: String
    var deckNames: [String]
    var tags: [String]

    var id: Int64 {
        noteId
    }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case weight
        case edgeType = "edge_type"
        case edgeSource = "edge_source"
        case textPreview = "text_preview"
        case deckNames = "deck_names"
        case tags
    }
}

struct NoteLinksResponse: Codable {
    var focusNoteId: Int64
    var relatedNotes: [NoteLink]

    enum CodingKeys: String, CodingKey {
        case focusNoteId = "focus_note_id"
        case relatedNotes = "related_notes"
    }
}

struct TopicNeighborhoodRequest: Codable {
    var topicId: Int64
    var maxHops: Int = 2
    var limitPerHop: Int = 20

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case maxHops = "max_hops"
        case limitPerHop = "limit_per_hop"
    }
}

struct TopicNodeSummary: Codable, Identifiable {
    var topicId: Int64
    var path: String
    var label: String
    var noteCount: Int64

    var id: Int64 {
        topicId
    }

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case path
        case label
        case noteCount = "note_count"
    }
}

struct TopicEdgeView: Codable, Identifiable {
    var sourceTopicId: Int64
    var targetTopicId: Int64
    var edgeType: KnowledgeGraphEdgeType
    var edgeSource: KnowledgeGraphEdgeSource
    var weight: Float

    var id: String {
        "\(sourceTopicId)-\(targetTopicId)-\(edgeType.rawValue)-\(edgeSource.rawValue)"
    }

    enum CodingKeys: String, CodingKey {
        case sourceTopicId = "source_topic_id"
        case targetTopicId = "target_topic_id"
        case edgeType = "edge_type"
        case edgeSource = "edge_source"
        case weight
    }
}

struct TopicNeighborhoodResponse: Codable {
    var rootTopicId: Int64
    var topics: [TopicNodeSummary]
    var edges: [TopicEdgeView]

    enum CodingKeys: String, CodingKey {
        case rootTopicId = "root_topic_id"
        case topics
        case edges
    }
}

struct DuplicateDetail: Codable, Identifiable {
    var noteId: Int64
    var similarity: Double
    var text: String
    var deckNames: [String]
    var tags: [String]

    var id: Int64 {
        noteId
    }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case similarity
        case text
        case deckNames = "deck_names"
        case tags
    }
}

struct DuplicateCluster: Codable, Identifiable {
    var representativeId: Int64
    var representativeText: String
    var duplicates: [DuplicateDetail]
    var deckNames: [String]
    var tags: [String]

    var id: Int64 {
        representativeId
    }

    var size: Int {
        1 + duplicates.count
    }

    enum CodingKeys: String, CodingKey {
        case representativeId = "representative_id"
        case representativeText = "representative_text"
        case duplicates
        case deckNames = "deck_names"
        case tags
    }
}
