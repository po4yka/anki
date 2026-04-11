import Foundation

// MARK: - Knowledge Graph

public enum KnowledgeGraphEdgeType: String, Codable {
    case similar
    case prerequisite
    case related
    case crossReference = "cross_reference"
    case specialization
}

public enum KnowledgeGraphEdgeSource: String, Codable {
    case embedding
    case tagCooccurrence = "tag_cooccurrence"
    case reviewInference = "review_inference"
    case wikilink
    case taxonomy
    case topicCooccurrence = "topic_cooccurrence"
    case manual
}

public struct KnowledgeGraphStatus: Codable {
    public var conceptEdgeCount: Int
    public var topicEdgeCount: Int
    public var lastRefreshedAt: String?
    public var similarityAvailable: Bool
    public var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case conceptEdgeCount = "concept_edge_count"
        case topicEdgeCount = "topic_edge_count"
        case lastRefreshedAt = "last_refreshed_at"
        case similarityAvailable = "similarity_available"
        case warnings
    }
}

public struct RefreshKnowledgeGraphRequest: Codable {
    public var rebuildConceptEdges: Bool = true
    public var rebuildTopicEdges: Bool = true
    public var noteSimilarityLimit: Int = 10

    enum CodingKeys: String, CodingKey {
        case rebuildConceptEdges = "rebuild_concept_edges"
        case rebuildTopicEdges = "rebuild_topic_edges"
        case noteSimilarityLimit = "note_similarity_limit"
    }

    public init(
        rebuildConceptEdges: Bool = true,
        rebuildTopicEdges: Bool = true,
        noteSimilarityLimit: Int = 10
    ) {
        self.rebuildConceptEdges = rebuildConceptEdges
        self.rebuildTopicEdges = rebuildTopicEdges
        self.noteSimilarityLimit = noteSimilarityLimit
    }
}

public struct RefreshKnowledgeGraphResponse: Codable {
    public var conceptTagEdgesWritten: Int
    public var conceptSimilarityEdgesWritten: Int
    public var topicSpecializationEdgesWritten: Int
    public var topicCooccurrenceEdgesWritten: Int
    public var conceptEdgeCount: Int
    public var topicEdgeCount: Int
    public var warnings: [String]

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

public struct NoteLinksRequest: Codable {
    public var noteId: Int64
    public var limit: Int = 12

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case limit
    }

    public init(noteId: Int64, limit: Int = 12) {
        self.noteId = noteId
        self.limit = limit
    }
}

public struct NoteLink: Codable, Identifiable {
    public var noteId: Int64
    public var weight: Float
    public var edgeType: KnowledgeGraphEdgeType
    public var edgeSource: KnowledgeGraphEdgeSource
    public var textPreview: String
    public var deckNames: [String]
    public var tags: [String]

    public var id: Int64 {
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

public struct NoteLinksResponse: Codable {
    public var focusNoteId: Int64
    public var relatedNotes: [NoteLink]

    enum CodingKeys: String, CodingKey {
        case focusNoteId = "focus_note_id"
        case relatedNotes = "related_notes"
    }
}

public struct TopicNeighborhoodRequest: Codable {
    public var topicId: Int64
    public var maxHops: Int = 2
    public var limitPerHop: Int = 20

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case maxHops = "max_hops"
        case limitPerHop = "limit_per_hop"
    }

    public init(topicId: Int64, maxHops: Int = 2, limitPerHop: Int = 20) {
        self.topicId = topicId
        self.maxHops = maxHops
        self.limitPerHop = limitPerHop
    }
}

public struct TopicNodeSummary: Codable, Identifiable {
    public var topicId: Int64
    public var path: String
    public var label: String
    public var noteCount: Int64

    public var id: Int64 {
        topicId
    }

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case path
        case label
        case noteCount = "note_count"
    }
}

public struct TopicEdgeView: Codable, Identifiable {
    public var sourceTopicId: Int64
    public var targetTopicId: Int64
    public var edgeType: KnowledgeGraphEdgeType
    public var edgeSource: KnowledgeGraphEdgeSource
    public var weight: Float

    public var id: String {
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

public struct TopicNeighborhoodResponse: Codable {
    public var rootTopicId: Int64
    public var topics: [TopicNodeSummary]
    public var edges: [TopicEdgeView]

    enum CodingKeys: String, CodingKey {
        case rootTopicId = "root_topic_id"
        case topics
        case edges
    }
}

public struct DuplicateDetail: Codable, Identifiable {
    public var noteId: Int64
    public var similarity: Double
    public var text: String
    public var deckNames: [String]
    public var tags: [String]

    public var id: Int64 {
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

public struct DuplicateCluster: Codable, Identifiable {
    public var representativeId: Int64
    public var representativeText: String
    public var duplicates: [DuplicateDetail]
    public var deckNames: [String]
    public var tags: [String]

    public var id: Int64 {
        representativeId
    }

    public var size: Int {
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
