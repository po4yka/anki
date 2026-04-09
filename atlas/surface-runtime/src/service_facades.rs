use std::path::PathBuf;
use std::sync::Arc;

use analytics::AnalyticsError;
use analytics::service::AnalyticsService;
use indexer::embeddings::EmbeddingProvider;
use indexer::vector::VectorRepository;
use search::error::{RerankError, SearchError};
use search::reranker::Reranker;
use search::service::SearchService;
use serde_json::Value;
use surface_contracts::analytics::{
    DuplicateCluster, DuplicateStats, LabelingStats, TaxonomyLoadSummary, TopicCoverage, TopicGap,
    WeakNote,
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
