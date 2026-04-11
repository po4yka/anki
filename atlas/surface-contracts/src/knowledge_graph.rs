use common::types::{NoteId, TopicId};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeGraphEdgeType {
    Similar,
    Prerequisite,
    Related,
    CrossReference,
    #[default]
    Specialization,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeGraphEdgeSource {
    Embedding,
    TagCooccurrence,
    ReviewInference,
    Wikilink,
    Taxonomy,
    TopicCooccurrence,
    #[default]
    Manual,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct KnowledgeGraphStatus {
    pub concept_edge_count: usize,
    pub topic_edge_count: usize,
    pub last_refreshed_at: Option<String>,
    pub similarity_available: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RefreshKnowledgeGraphRequest {
    #[serde(default = "default_true")]
    pub rebuild_concept_edges: bool,
    #[serde(default = "default_true")]
    pub rebuild_topic_edges: bool,
    #[serde(default = "default_note_similarity_limit")]
    pub note_similarity_limit: usize,
}

impl Default for RefreshKnowledgeGraphRequest {
    fn default() -> Self {
        Self {
            rebuild_concept_edges: default_true(),
            rebuild_topic_edges: default_true(),
            note_similarity_limit: default_note_similarity_limit(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct RefreshKnowledgeGraphResponse {
    pub concept_tag_edges_written: usize,
    pub concept_similarity_edges_written: usize,
    pub topic_specialization_edges_written: usize,
    pub topic_cooccurrence_edges_written: usize,
    pub concept_edge_count: usize,
    pub topic_edge_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NoteLinksRequest {
    pub note_id: NoteId,
    #[serde(default = "default_note_links_limit")]
    pub limit: usize,
}

impl Default for NoteLinksRequest {
    fn default() -> Self {
        Self {
            note_id: NoteId(0),
            limit: default_note_links_limit(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct NoteLink {
    pub note_id: NoteId,
    pub weight: OrderedFloatDef,
    pub edge_type: KnowledgeGraphEdgeType,
    pub edge_source: KnowledgeGraphEdgeSource,
    pub text_preview: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub deck_names: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct NoteLinksResponse {
    pub focus_note_id: NoteId,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub related_notes: Vec<NoteLink>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TopicNeighborhoodRequest {
    pub topic_id: TopicId,
    #[serde(default = "default_topic_max_hops")]
    pub max_hops: usize,
    #[serde(default = "default_limit_per_hop")]
    pub limit_per_hop: usize,
}

impl Default for TopicNeighborhoodRequest {
    fn default() -> Self {
        Self {
            topic_id: TopicId(0),
            max_hops: default_topic_max_hops(),
            limit_per_hop: default_limit_per_hop(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct TopicNodeSummary {
    pub topic_id: TopicId,
    pub path: String,
    pub label: String,
    pub note_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct TopicEdgeView {
    pub source_topic_id: TopicId,
    pub target_topic_id: TopicId,
    pub edge_type: KnowledgeGraphEdgeType,
    pub edge_source: KnowledgeGraphEdgeSource,
    pub weight: OrderedFloatDef,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct TopicNeighborhoodResponse {
    pub root_topic_id: TopicId,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub topics: Vec<TopicNodeSummary>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub edges: Vec<TopicEdgeView>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq)]
#[serde(transparent)]
pub struct OrderedFloatDef(pub f32);

impl Eq for OrderedFloatDef {}

impl From<f32> for OrderedFloatDef {
    fn from(value: f32) -> Self {
        Self(value)
    }
}

impl From<OrderedFloatDef> for f32 {
    fn from(value: OrderedFloatDef) -> Self {
        value.0
    }
}

const fn default_true() -> bool {
    true
}

const fn default_note_similarity_limit() -> usize {
    10
}

const fn default_note_links_limit() -> usize {
    12
}

const fn default_topic_max_hops() -> usize {
    2
}

const fn default_limit_per_hop() -> usize {
    20
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn knowledge_graph_contracts_round_trip() {
        let payload = (
            KnowledgeGraphStatus {
                concept_edge_count: 10,
                topic_edge_count: 4,
                last_refreshed_at: Some("2026-04-10T00:00:00Z".into()),
                similarity_available: true,
                warnings: vec!["warn".into()],
            },
            RefreshKnowledgeGraphRequest::default(),
            RefreshKnowledgeGraphResponse {
                concept_tag_edges_written: 2,
                concept_similarity_edges_written: 6,
                topic_specialization_edges_written: 3,
                topic_cooccurrence_edges_written: 5,
                concept_edge_count: 8,
                topic_edge_count: 8,
                warnings: vec!["partial".into()],
            },
            NoteLinksResponse {
                focus_note_id: NoteId(1),
                related_notes: vec![NoteLink {
                    note_id: NoteId(2),
                    weight: OrderedFloatDef(0.8),
                    edge_type: KnowledgeGraphEdgeType::Related,
                    edge_source: KnowledgeGraphEdgeSource::TagCooccurrence,
                    text_preview: "preview".into(),
                    deck_names: vec!["Default".into()],
                    tags: vec!["rust".into()],
                }],
            },
            TopicNeighborhoodResponse {
                root_topic_id: TopicId(1),
                topics: vec![TopicNodeSummary {
                    topic_id: TopicId(1),
                    path: "rust/ownership".into(),
                    label: "Ownership".into(),
                    note_count: 3,
                }],
                edges: vec![TopicEdgeView {
                    source_topic_id: TopicId(2),
                    target_topic_id: TopicId(1),
                    edge_type: KnowledgeGraphEdgeType::Specialization,
                    edge_source: KnowledgeGraphEdgeSource::Taxonomy,
                    weight: OrderedFloatDef(1.0),
                }],
            },
        );

        let json = serde_json::to_string(&payload).expect("serialize contracts");
        let decoded: (
            KnowledgeGraphStatus,
            RefreshKnowledgeGraphRequest,
            RefreshKnowledgeGraphResponse,
            NoteLinksResponse,
            TopicNeighborhoodResponse,
        ) = serde_json::from_str(&json).expect("deserialize contracts");

        assert_eq!(decoded, payload);
    }

    #[test]
    fn defaults_match_expected_plan_values() {
        let refresh = RefreshKnowledgeGraphRequest::default();
        assert!(refresh.rebuild_concept_edges);
        assert!(refresh.rebuild_topic_edges);
        assert_eq!(refresh.note_similarity_limit, 10);

        let links = NoteLinksRequest {
            note_id: NoteId(1),
            ..Default::default()
        };
        assert_eq!(links.limit, 12);

        let neighborhood = TopicNeighborhoodRequest {
            topic_id: TopicId(1),
            ..Default::default()
        };
        assert_eq!(neighborhood.max_hops, 2);
        assert_eq!(neighborhood.limit_per_hop, 20);
    }
}
