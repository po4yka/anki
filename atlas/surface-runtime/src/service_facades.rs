use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use analytics::AnalyticsError;
use analytics::service::AnalyticsService;
use chrono::Utc;
use indexer::embeddings::EmbeddingProvider;
use indexer::vector::VectorRepository;
use knowledge_graph::discovery::similarity::discover_similarity_edges;
use knowledge_graph::discovery::tags::discover_tag_cooccurrence_edges;
use knowledge_graph::models::{
    EdgeSource as DomainEdgeSource, EdgeType as DomainEdgeType, TopicEdge,
};
use knowledge_graph::query;
use knowledge_graph::{
    KnowledgeGraphError, KnowledgeGraphRepository, SqlxKnowledgeGraphRepository,
};
use search::error::{RerankError, SearchError};
use search::reranker::Reranker;
use search::service::SearchService;
use serde_json::Value;
use surface_contracts::analytics::{
    DuplicateCluster, DuplicateStats, LabelingStats, TaxonomyLoadSummary, TopicCoverage, TopicGap,
    WeakNote,
};
use surface_contracts::knowledge_graph::{
    KnowledgeGraphEdgeSource, KnowledgeGraphEdgeType, KnowledgeGraphStatus, NoteLink,
    NoteLinksRequest, NoteLinksResponse, RefreshKnowledgeGraphRequest,
    RefreshKnowledgeGraphResponse, TopicEdgeView, TopicNeighborhoodRequest,
    TopicNeighborhoodResponse, TopicNodeSummary,
};
use surface_contracts::search::{
    ChunkSearchRequest, ChunkSearchResponse, SearchRequest, SearchResponse,
};

use crate::contracts::{
    build_chunk_search_params, build_search_params, chunk_search_response, duplicates,
    labeling_stats, search_response, taxonomy_load_summary, topic_coverage, topic_gaps, weak_notes,
};
use crate::error::SurfaceError;

pub(crate) type SharedEmbeddingProvider = Arc<dyn EmbeddingProvider>;
pub(crate) type SharedVectorRepository = Arc<dyn VectorRepository>;
pub(crate) type SharedReranker = Arc<dyn Reranker>;

pub(crate) fn map_search_error(error: SearchError) -> SurfaceError {
    match error {
        SearchError::InvalidRequest(message) => SurfaceError::InvalidInput(message),
        SearchError::Database(source) => SurfaceError::Database(source),
        SearchError::Embedding(source) => SurfaceError::Embedding(source),
        SearchError::VectorStore(source) => SurfaceError::VectorStore(source),
        SearchError::Rerank(rerank_err) => match rerank_err {
            RerankError::Http { status, body } => SurfaceError::RerankHttp { status, body },
            RerankError::Transport { message } => SurfaceError::RerankTransport(message),
            RerankError::Protocol { message } => SurfaceError::RerankProtocol(message),
        },
    }
}

pub(crate) fn map_analytics_error(error: AnalyticsError) -> SurfaceError {
    match error {
        AnalyticsError::Database(source) => SurfaceError::Database(source),
        AnalyticsError::Embedding(source) => SurfaceError::Embedding(source),
        AnalyticsError::VectorStore(source) => SurfaceError::VectorStore(source),
        AnalyticsError::YamlParse(source) => SurfaceError::InvalidInput(source.to_string()),
        AnalyticsError::Io(source) => SurfaceError::Io(source),
        AnalyticsError::TopicNotFound(topic_path) => SurfaceError::NotFound(topic_path),
        AnalyticsError::Internal(message) => SurfaceError::Provider(message),
    }
}

pub(crate) fn map_knowledge_graph_error(error: KnowledgeGraphError) -> SurfaceError {
    SurfaceError::KnowledgeGraph(error)
}

#[async_trait::async_trait]
#[cfg_attr(test, mockall::automock)]
pub trait SearchFacade: Send + Sync {
    async fn search(
        &self,
        request: &SearchRequest,
    ) -> std::result::Result<SearchResponse, SurfaceError>;

    async fn search_chunks(
        &self,
        request: &ChunkSearchRequest,
    ) -> std::result::Result<ChunkSearchResponse, SurfaceError>;
}

#[async_trait::async_trait]
#[cfg_attr(test, mockall::automock)]
pub trait AnalyticsFacade: Send + Sync {
    async fn load_taxonomy(
        &self,
        yaml_path: Option<PathBuf>,
    ) -> std::result::Result<TaxonomyLoadSummary, SurfaceError>;
    async fn label_notes(
        &self,
        yaml_path: Option<PathBuf>,
        min_confidence: f32,
    ) -> std::result::Result<LabelingStats, SurfaceError>;
    async fn get_taxonomy_tree(
        &self,
        root_path: Option<String>,
    ) -> std::result::Result<Vec<Value>, SurfaceError>;
    async fn get_coverage(
        &self,
        topic_path: String,
        include_subtree: bool,
    ) -> std::result::Result<Option<TopicCoverage>, SurfaceError>;
    async fn get_gaps(
        &self,
        topic_path: String,
        min_coverage: i64,
    ) -> std::result::Result<Vec<TopicGap>, SurfaceError>;
    async fn get_weak_notes(
        &self,
        topic_path: String,
        max_results: i64,
    ) -> std::result::Result<Vec<WeakNote>, SurfaceError>;
    async fn find_duplicates(
        &self,
        threshold: f64,
        max_clusters: usize,
        deck_filter: Option<Vec<String>>,
        tag_filter: Option<Vec<String>>,
    ) -> std::result::Result<(Vec<DuplicateCluster>, DuplicateStats), SurfaceError>;
}

#[async_trait::async_trait]
#[cfg_attr(test, mockall::automock)]
pub trait KnowledgeGraphFacade: Send + Sync {
    async fn status(&self) -> std::result::Result<KnowledgeGraphStatus, SurfaceError>;
    async fn refresh(
        &self,
        request: &RefreshKnowledgeGraphRequest,
    ) -> std::result::Result<RefreshKnowledgeGraphResponse, SurfaceError>;
    async fn note_links(
        &self,
        request: &NoteLinksRequest,
    ) -> std::result::Result<NoteLinksResponse, SurfaceError>;
    async fn topic_neighborhood(
        &self,
        request: &TopicNeighborhoodRequest,
    ) -> std::result::Result<TopicNeighborhoodResponse, SurfaceError>;
}

pub(crate) struct NoopKnowledgeGraphFacade;

#[async_trait::async_trait]
impl KnowledgeGraphFacade for NoopKnowledgeGraphFacade {
    async fn status(&self) -> std::result::Result<KnowledgeGraphStatus, SurfaceError> {
        Ok(KnowledgeGraphStatus::default())
    }

    async fn refresh(
        &self,
        _request: &RefreshKnowledgeGraphRequest,
    ) -> std::result::Result<RefreshKnowledgeGraphResponse, SurfaceError> {
        Err(SurfaceError::Configuration(
            "knowledge graph not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn note_links(
        &self,
        _request: &NoteLinksRequest,
    ) -> std::result::Result<NoteLinksResponse, SurfaceError> {
        Err(SurfaceError::Configuration(
            "knowledge graph not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn topic_neighborhood(
        &self,
        _request: &TopicNeighborhoodRequest,
    ) -> std::result::Result<TopicNeighborhoodResponse, SurfaceError> {
        Err(SurfaceError::Configuration(
            "knowledge graph not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }
}

pub(crate) struct SearchFacadeImpl {
    pub(crate) inner:
        SearchService<SharedEmbeddingProvider, SharedVectorRepository, SharedReranker>,
}

#[async_trait::async_trait]
impl SearchFacade for SearchFacadeImpl {
    async fn search(
        &self,
        request: &SearchRequest,
    ) -> std::result::Result<SearchResponse, SurfaceError> {
        let params = build_search_params(request).map_err(map_search_error)?;
        self.inner
            .search(&params)
            .await
            .map(search_response)
            .map_err(map_search_error)
    }

    async fn search_chunks(
        &self,
        request: &ChunkSearchRequest,
    ) -> std::result::Result<ChunkSearchResponse, SurfaceError> {
        let params = build_chunk_search_params(request).map_err(map_search_error)?;
        self.inner
            .search_chunks(&params)
            .await
            .map(chunk_search_response)
            .map_err(map_search_error)
    }
}

pub(crate) struct AnalyticsFacadeImpl {
    pub(crate) inner: AnalyticsService<SharedEmbeddingProvider, SharedVectorRepository>,
}

#[async_trait::async_trait]
impl AnalyticsFacade for AnalyticsFacadeImpl {
    async fn load_taxonomy(
        &self,
        yaml_path: Option<PathBuf>,
    ) -> std::result::Result<TaxonomyLoadSummary, SurfaceError> {
        self.inner
            .load_taxonomy(yaml_path.as_deref())
            .await
            .map(|taxonomy| taxonomy_load_summary(&taxonomy))
            .map_err(map_analytics_error)
    }

    async fn label_notes(
        &self,
        yaml_path: Option<PathBuf>,
        min_confidence: f32,
    ) -> std::result::Result<LabelingStats, SurfaceError> {
        let taxonomy = if let Some(path) = yaml_path {
            Some(
                self.inner
                    .load_taxonomy(Some(&path))
                    .await
                    .map_err(map_analytics_error)?,
            )
        } else {
            None
        };
        self.inner
            .label_notes(taxonomy.as_ref(), min_confidence)
            .await
            .map(labeling_stats)
            .map_err(map_analytics_error)
    }

    async fn get_taxonomy_tree(
        &self,
        root_path: Option<String>,
    ) -> std::result::Result<Vec<Value>, SurfaceError> {
        self.inner
            .get_taxonomy_tree(root_path.as_deref())
            .await
            .map_err(map_analytics_error)
    }

    async fn get_coverage(
        &self,
        topic_path: String,
        include_subtree: bool,
    ) -> std::result::Result<Option<TopicCoverage>, SurfaceError> {
        self.inner
            .get_coverage(&topic_path, include_subtree)
            .await
            .map(|coverage| coverage.map(topic_coverage))
            .map_err(map_analytics_error)
    }

    async fn get_gaps(
        &self,
        topic_path: String,
        min_coverage: i64,
    ) -> std::result::Result<Vec<TopicGap>, SurfaceError> {
        self.inner
            .get_gaps(&topic_path, min_coverage)
            .await
            .map(topic_gaps)
            .map_err(map_analytics_error)
    }

    async fn get_weak_notes(
        &self,
        topic_path: String,
        max_results: i64,
    ) -> std::result::Result<Vec<WeakNote>, SurfaceError> {
        self.inner
            .get_weak_notes(&topic_path, max_results)
            .await
            .map(weak_notes)
            .map_err(map_analytics_error)
    }

    async fn find_duplicates(
        &self,
        threshold: f64,
        max_clusters: usize,
        deck_filter: Option<Vec<String>>,
        tag_filter: Option<Vec<String>>,
    ) -> std::result::Result<(Vec<DuplicateCluster>, DuplicateStats), SurfaceError> {
        self.inner
            .find_duplicates(
                threshold,
                max_clusters,
                deck_filter.as_deref(),
                tag_filter.as_deref(),
            )
            .await
            .map(|(clusters, stats)| duplicates(clusters, stats))
            .map_err(map_analytics_error)
    }
}

pub(crate) struct KnowledgeGraphFacadeImpl {
    pub(crate) pool: sqlx::PgPool,
    pub(crate) repo: Arc<SqlxKnowledgeGraphRepository>,
    pub(crate) vector_store: SharedVectorRepository,
}

impl KnowledgeGraphFacadeImpl {
    const LAST_REFRESHED_KEY: &str = "knowledge_graph_last_refreshed_at";

    async fn similarity_status(&self) -> (bool, Option<String>) {
        match self.vector_store.collection_dimension().await {
            Ok(Some(_)) => (true, None),
            Ok(None) => (
                false,
                Some("Vector collection is missing; similarity edges were skipped.".to_string()),
            ),
            Err(error) => (
                false,
                Some(format!("Similarity discovery unavailable: {error}")),
            ),
        }
    }

    async fn last_refreshed_at(&self) -> std::result::Result<Option<String>, SurfaceError> {
        sqlx::query_scalar::<_, String>("SELECT value #>> '{}' FROM sync_metadata WHERE key = $1")
            .bind(Self::LAST_REFRESHED_KEY)
            .fetch_optional(&self.pool)
            .await
            .map_err(SurfaceError::Database)
    }

    async fn store_last_refreshed_at(&self) -> std::result::Result<(), SurfaceError> {
        let now = Utc::now().to_rfc3339();
        sqlx::query(
            "INSERT INTO sync_metadata (key, value) VALUES ($1, to_jsonb($2::text))
             ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()",
        )
        .bind(Self::LAST_REFRESHED_KEY)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(SurfaceError::Database)?;
        Ok(())
    }

    async fn active_note_ids(&self) -> std::result::Result<Vec<i64>, SurfaceError> {
        sqlx::query_scalar("SELECT note_id FROM notes WHERE deleted_at IS NULL ORDER BY note_id")
            .fetch_all(&self.pool)
            .await
            .map_err(SurfaceError::Database)
    }

    async fn rebuild_similarity_edges(
        &self,
        limit: usize,
    ) -> std::result::Result<usize, SurfaceError> {
        let note_ids = self.active_note_ids().await?;
        let mut by_pair = HashMap::<(i64, i64), f32>::new();

        for note_id in note_ids {
            let hits = self
                .vector_store
                .find_similar_to_note(note_id, limit, 0.7, None, None)
                .await
                .map_err(SurfaceError::VectorStore)?;

            for hit in hits {
                if hit.note_id == note_id {
                    continue;
                }
                let key = if note_id < hit.note_id {
                    (note_id, hit.note_id)
                } else {
                    (hit.note_id, note_id)
                };
                by_pair
                    .entry(key)
                    .and_modify(|score| *score = score.max(hit.score))
                    .or_insert(hit.score);
            }
        }

        let pairs: Vec<(i64, i64, f32)> = by_pair
            .into_iter()
            .map(|((source_note_id, target_note_id), score)| {
                (source_note_id, target_note_id, score)
            })
            .collect();

        discover_similarity_edges(self.repo.as_ref(), &pairs)
            .await
            .map_err(map_knowledge_graph_error)
    }

    async fn rebuild_topic_specialization_edges(
        &self,
    ) -> std::result::Result<usize, SurfaceError> {
        #[derive(sqlx::FromRow)]
        struct TopicPathRow {
            topic_id: i32,
            path: String,
        }

        let rows: Vec<TopicPathRow> = sqlx::query_as(
            "SELECT topic_id, path FROM topics ORDER BY path",
        )
        .fetch_all(&self.pool)
        .await
        .map_err(SurfaceError::Database)?;

        let path_to_id: HashMap<String, i32> =
            rows.iter().map(|row| (row.path.clone(), row.topic_id)).collect();

        let edges: Vec<TopicEdge> = rows
            .into_iter()
            .filter_map(|row| {
                let (parent_path, _) = row.path.rsplit_once('/')?;
                let parent_id = path_to_id.get(parent_path)?;
                Some(TopicEdge {
                    source_topic_id: row.topic_id,
                    target_topic_id: *parent_id,
                    edge_type: DomainEdgeType::Specialization,
                    edge_source: DomainEdgeSource::Taxonomy,
                    weight: 1.0,
                })
            })
            .collect();

        if edges.is_empty() {
            return Ok(0);
        }

        self.repo
            .upsert_topic_edges(&edges)
            .await
            .map_err(map_knowledge_graph_error)
    }

    async fn rebuild_topic_cooccurrence_edges(
        &self,
    ) -> std::result::Result<usize, SurfaceError> {
        #[derive(sqlx::FromRow)]
        struct TopicPairRow {
            topic_a: i32,
            topic_b: i32,
            weight: Option<f32>,
        }

        let rows: Vec<TopicPairRow> = sqlx::query_as(
            "WITH topic_counts AS (
                 SELECT topic_id, COUNT(*)::real AS note_count
                 FROM note_topics
                 GROUP BY topic_id
             ),
             topic_pairs AS (
                 SELECT a.topic_id AS topic_a, b.topic_id AS topic_b, COUNT(*)::real AS shared_notes
                 FROM note_topics a
                 JOIN note_topics b
                   ON a.note_id = b.note_id
                  AND a.topic_id < b.topic_id
                 GROUP BY a.topic_id, b.topic_id
             )
             SELECT tp.topic_a, tp.topic_b,
                    (tp.shared_notes / NULLIF(GREATEST(tc_a.note_count, tc_b.note_count), 0)) AS weight
             FROM topic_pairs tp
             JOIN topic_counts tc_a ON tc_a.topic_id = tp.topic_a
             JOIN topic_counts tc_b ON tc_b.topic_id = tp.topic_b
             ORDER BY weight DESC
             LIMIT 5000",
        )
        .fetch_all(&self.pool)
        .await
        .map_err(SurfaceError::Database)?;

        let edges: Vec<TopicEdge> = rows
            .iter()
            .flat_map(|row| {
                let weight = row.weight.unwrap_or(0.5);
                [
                    TopicEdge {
                        source_topic_id: row.topic_a,
                        target_topic_id: row.topic_b,
                        edge_type: DomainEdgeType::Related,
                        edge_source: DomainEdgeSource::TopicCooccurrence,
                        weight,
                    },
                    TopicEdge {
                        source_topic_id: row.topic_b,
                        target_topic_id: row.topic_a,
                        edge_type: DomainEdgeType::Related,
                        edge_source: DomainEdgeSource::TopicCooccurrence,
                        weight,
                    },
                ]
            })
            .collect();

        if edges.is_empty() {
            return Ok(0);
        }

        self.repo
            .upsert_topic_edges(&edges)
            .await
            .map_err(map_knowledge_graph_error)
    }

    async fn hydrate_note_links(
        &self,
        focus_note_id: i64,
        edges: &[knowledge_graph::ConceptEdge],
    ) -> std::result::Result<Vec<NoteLink>, SurfaceError> {
        #[derive(sqlx::FromRow)]
        struct NoteLinkRow {
            note_id: i64,
            text_preview: String,
            deck_names: Vec<String>,
            tags: Vec<String>,
        }

        let related_ids: Vec<i64> = edges
            .iter()
            .map(|edge| {
                if edge.source_note_id == focus_note_id {
                    edge.target_note_id
                } else {
                    edge.source_note_id
                }
            })
            .collect();

        if related_ids.is_empty() {
            return Ok(Vec::new());
        }

        let rows: Vec<NoteLinkRow> = sqlx::query_as(
            "SELECT
                 n.note_id,
                 n.normalized_text AS text_preview,
                 COALESCE(array_remove(array_agg(DISTINCT d.name), NULL), ARRAY[]::text[]) AS deck_names,
                 COALESCE(n.tags, ARRAY[]::text[]) AS tags
             FROM notes n
             LEFT JOIN cards c ON c.note_id = n.note_id
             LEFT JOIN decks d ON d.deck_id = c.deck_id
             WHERE n.note_id = ANY($1)
             GROUP BY n.note_id, n.normalized_text, n.tags",
        )
        .bind(&related_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(SurfaceError::Database)?;

        let by_id: HashMap<i64, NoteLinkRow> =
            rows.into_iter().map(|row| (row.note_id, row)).collect();

        Ok(edges
            .iter()
            .filter_map(|edge| {
                let linked_note_id = if edge.source_note_id == focus_note_id {
                    edge.target_note_id
                } else {
                    edge.source_note_id
                };
                let row = by_id.get(&linked_note_id)?;
                Some(NoteLink {
                    note_id: linked_note_id.into(),
                    weight: edge.weight.into(),
                    edge_type: map_edge_type(edge.edge_type),
                    edge_source: map_edge_source(edge.edge_source),
                    text_preview: row.text_preview.clone(),
                    deck_names: row.deck_names.clone(),
                    tags: row.tags.clone(),
                })
            })
            .collect())
    }

    async fn hydrate_topic_neighborhood(
        &self,
        request: &TopicNeighborhoodRequest,
        topic_ids: &[i32],
        edges: &[TopicEdge],
    ) -> std::result::Result<TopicNeighborhoodResponse, SurfaceError> {
        #[derive(sqlx::FromRow)]
        struct TopicSummaryRow {
            topic_id: i64,
            path: String,
            label: String,
            note_count: i64,
        }

        let db_topic_ids: Vec<i64> = topic_ids.iter().map(|id| i64::from(*id)).collect();
        let rows: Vec<TopicSummaryRow> = sqlx::query_as(
            "SELECT
                 t.topic_id::bigint AS topic_id,
                 t.path,
                 t.label,
                 COUNT(nt.note_id)::bigint AS note_count
             FROM topics t
             LEFT JOIN note_topics nt ON nt.topic_id = t.topic_id
             WHERE t.topic_id = ANY($1)
             GROUP BY t.topic_id, t.path, t.label
             ORDER BY t.path",
        )
        .bind(&db_topic_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(SurfaceError::Database)?;

        if !rows.iter().any(|row| row.topic_id == request.topic_id.0) {
            return Err(SurfaceError::NotFound(format!(
                "topic {}",
                request.topic_id.0
            )));
        }

        Ok(TopicNeighborhoodResponse {
            root_topic_id: request.topic_id,
            topics: rows
                .into_iter()
                .map(|row| TopicNodeSummary {
                    topic_id: row.topic_id.into(),
                    path: row.path,
                    label: row.label,
                    note_count: row.note_count,
                })
                .collect(),
            edges: edges
                .iter()
                .map(|edge| TopicEdgeView {
                    source_topic_id: i64::from(edge.source_topic_id).into(),
                    target_topic_id: i64::from(edge.target_topic_id).into(),
                    edge_type: map_edge_type(edge.edge_type),
                    edge_source: map_edge_source(edge.edge_source),
                    weight: edge.weight.into(),
                })
                .collect(),
        })
    }
}

#[async_trait::async_trait]
impl KnowledgeGraphFacade for KnowledgeGraphFacadeImpl {
    async fn status(&self) -> std::result::Result<KnowledgeGraphStatus, SurfaceError> {
        let (concept_edge_count, topic_edge_count) = self
            .repo
            .edge_count()
            .await
            .map_err(map_knowledge_graph_error)?;
        let (similarity_available, warning) = self.similarity_status().await;
        let mut warnings = Vec::new();
        if let Some(warning) = warning {
            warnings.push(warning);
        }

        Ok(KnowledgeGraphStatus {
            concept_edge_count,
            topic_edge_count,
            last_refreshed_at: self.last_refreshed_at().await?,
            similarity_available,
            warnings,
        })
    }

    async fn refresh(
        &self,
        request: &RefreshKnowledgeGraphRequest,
    ) -> std::result::Result<RefreshKnowledgeGraphResponse, SurfaceError> {
        let mut response = RefreshKnowledgeGraphResponse::default();

        if request.rebuild_concept_edges {
            self.repo
                .delete_edges_by_source(DomainEdgeSource::Embedding)
                .await
                .map_err(map_knowledge_graph_error)?;
            self.repo
                .delete_edges_by_source(DomainEdgeSource::TagCooccurrence)
                .await
                .map_err(map_knowledge_graph_error)?;

            response.concept_tag_edges_written =
                discover_tag_cooccurrence_edges(&self.pool, self.repo.as_ref())
                    .await
                    .map_err(map_knowledge_graph_error)?;

            let (similarity_available, warning) = self.similarity_status().await;
            if similarity_available {
                match self
                    .rebuild_similarity_edges(request.note_similarity_limit)
                    .await
                {
                    Ok(count) => response.concept_similarity_edges_written = count,
                    Err(error) => response
                        .warnings
                        .push(format!("Similarity edges were skipped: {error}")),
                }
            } else if let Some(warning) = warning {
                response.warnings.push(warning);
            }
        }

        if request.rebuild_topic_edges {
            self.repo
                .delete_edges_by_source(DomainEdgeSource::Taxonomy)
                .await
                .map_err(map_knowledge_graph_error)?;
            self.repo
                .delete_edges_by_source(DomainEdgeSource::TopicCooccurrence)
                .await
                .map_err(map_knowledge_graph_error)?;

            response.topic_specialization_edges_written =
                self.rebuild_topic_specialization_edges().await?;
            response.topic_cooccurrence_edges_written =
                self.rebuild_topic_cooccurrence_edges().await?;
        }

        let (concept_edge_count, topic_edge_count) = self
            .repo
            .edge_count()
            .await
            .map_err(map_knowledge_graph_error)?;
        response.concept_edge_count = concept_edge_count;
        response.topic_edge_count = topic_edge_count;

        if request.rebuild_concept_edges || request.rebuild_topic_edges {
            self.store_last_refreshed_at().await?;
        }

        Ok(response)
    }

    async fn note_links(
        &self,
        request: &NoteLinksRequest,
    ) -> std::result::Result<NoteLinksResponse, SurfaceError> {
        let edges = query::see_also(
            self.repo.as_ref(),
            request.note_id.0,
            request.limit,
        )
        .await
        .map_err(map_knowledge_graph_error)?;

        Ok(NoteLinksResponse {
            focus_note_id: request.note_id,
            related_notes: self
                .hydrate_note_links(request.note_id.0, &edges)
                .await?,
        })
    }

    async fn topic_neighborhood(
        &self,
        request: &TopicNeighborhoodRequest,
    ) -> std::result::Result<TopicNeighborhoodResponse, SurfaceError> {
        let (edges, topic_ids) = query::topic_neighborhood(
            self.repo.as_ref(),
            request.topic_id.0 as i32,
            request.max_hops,
            request.limit_per_hop,
        )
        .await
        .map_err(map_knowledge_graph_error)?;

        self.hydrate_topic_neighborhood(request, &topic_ids, &edges)
            .await
    }
}

fn map_edge_type(value: DomainEdgeType) -> KnowledgeGraphEdgeType {
    match value {
        DomainEdgeType::Similar => KnowledgeGraphEdgeType::Similar,
        DomainEdgeType::Prerequisite => KnowledgeGraphEdgeType::Prerequisite,
        DomainEdgeType::Related => KnowledgeGraphEdgeType::Related,
        DomainEdgeType::CrossReference => KnowledgeGraphEdgeType::CrossReference,
        DomainEdgeType::Specialization => KnowledgeGraphEdgeType::Specialization,
    }
}

fn map_edge_source(value: DomainEdgeSource) -> KnowledgeGraphEdgeSource {
    match value {
        DomainEdgeSource::Embedding => KnowledgeGraphEdgeSource::Embedding,
        DomainEdgeSource::TagCooccurrence => KnowledgeGraphEdgeSource::TagCooccurrence,
        DomainEdgeSource::ReviewInference => KnowledgeGraphEdgeSource::ReviewInference,
        DomainEdgeSource::Wikilink => KnowledgeGraphEdgeSource::Wikilink,
        DomainEdgeSource::Taxonomy => KnowledgeGraphEdgeSource::Taxonomy,
        DomainEdgeSource::TopicCooccurrence => KnowledgeGraphEdgeSource::TopicCooccurrence,
        DomainEdgeSource::Manual => KnowledgeGraphEdgeSource::Manual,
    }
}
