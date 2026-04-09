use std::env;
use std::path::PathBuf;
use std::sync::Arc;

use analytics::repository::SqlxAnalyticsRepository;
use analytics::service::AnalyticsService;
use common::config::{EmbeddingProviderKind, Settings};
use database::PgVectorRepository;
use database::create_pool;
use indexer::embeddings::{EmbeddingProvider, EmbeddingProviderConfig, create_embedding_provider};
use indexer::vector::VectorRepository;
use jobs::{JobManager, PgJobManager};
use search::repository::SqlxSearchReadRepository;
use search::reranker::CrossEncoderReranker;
use search::service::SearchService;
use sqlx::PgPool;

use crate::error::SurfaceError;
use crate::service_facades::{
    AnalyticsFacadeImpl, SearchFacadeImpl, SharedEmbeddingProvider, SharedReranker,
    SharedVectorRepository,
};
use crate::services::SurfaceServices;
use crate::workflows::{IndexingService, SyncExecutionService};

pub(crate) const EMBEDDING_VECTOR_SCHEMA: &str = "multimodal_v1";

#[derive(Debug, Clone, Copy, Default)]
pub struct BuildSurfaceServicesOptions {
    pub enable_direct_execution: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmbeddingFingerprint {
    pub(crate) model: String,
    pub(crate) dimension: usize,
    pub(crate) vector_schema: String,
}

pub(crate) fn build_embedding_config(
    settings: &Settings,
) -> Result<EmbeddingProviderConfig, SurfaceError> {
    let embedding = settings.embedding();
    let config = match embedding.provider {
        EmbeddingProviderKind::Mock => EmbeddingProviderConfig::Mock {
            dimension: embedding.dimension as usize,
        },
        EmbeddingProviderKind::OpenAi => EmbeddingProviderConfig::OpenAi {
            model: embedding.model,
            dimension: embedding.dimension as usize,
            batch_size: None,
            api_key: env::var("OPENAI_API_KEY").map_err(|_| {
                SurfaceError::Configuration(
                    "OPENAI_API_KEY must be set for the OpenAI embedding provider".into(),
                )
            })?,
        },
        EmbeddingProviderKind::Google => EmbeddingProviderConfig::Google {
            model: embedding.model,
            dimension: embedding.dimension as usize,
            batch_size: None,
            api_key: env::var("GEMINI_API_KEY")
                .or_else(|_| env::var("GOOGLE_API_KEY"))
                .map_err(|_| {
                    SurfaceError::Configuration(
                        "GEMINI_API_KEY or GOOGLE_API_KEY must be set for the Google embedding provider".into(),
                    )
                })?,
        },
        EmbeddingProviderKind::FastEmbed => {
            return Err(SurfaceError::Configuration(
                "FastEmbed provider requires the 'local-embeddings' feature on the indexer crate. \
                 Use ANKIATLAS_EMBEDDING_PROVIDER=openai or google for the server runtime."
                    .into(),
            ));
        }
    };

    Ok(config)
}

pub(crate) async fn load_sync_metadata_value(
    db: &PgPool,
    key: &str,
) -> Result<Option<String>, SurfaceError> {
    sqlx::query_scalar::<_, String>("SELECT value #>> '{}' FROM sync_metadata WHERE key = $1")
        .bind(key)
        .fetch_optional(db)
        .await
        .map_err(SurfaceError::Database)
}

pub(crate) async fn load_embedding_fingerprint(
    db: &PgPool,
) -> Result<Option<EmbeddingFingerprint>, SurfaceError> {
    let model = load_sync_metadata_value(db, "embedding_model").await?;
    let dimension = load_sync_metadata_value(db, "embedding_dimension").await?;
    let vector_schema = load_sync_metadata_value(db, "embedding_vector_schema").await?;

    let (Some(model), Some(dimension), Some(vector_schema)) = (model, dimension, vector_schema)
    else {
        return Ok(None);
    };

    let dimension = dimension.parse::<usize>().map_err(|e| {
        SurfaceError::Configuration(format!("invalid embedding_dimension value: {e}"))
    })?;

    Ok(Some(EmbeddingFingerprint {
        model,
        dimension,
        vector_schema,
    }))
}

pub(crate) fn validate_read_only_collection_state(
    current_dimension: Option<usize>,
    desired_dimension: usize,
    desired_model: &str,
    stored_fingerprint: Option<&EmbeddingFingerprint>,
) -> Result<(), SurfaceError> {
    let Some(current_dimension) = current_dimension else {
        if stored_fingerprint.is_some() {
            return Err(SurfaceError::ReindexRequired(
                "vector collection is missing".into(),
            ));
        }
        return Ok(());
    };

    if current_dimension != desired_dimension {
        return Err(SurfaceError::ReindexRequired(format!(
            "vector collection dimension is {current_dimension}, expected {desired_dimension}"
        )));
    }

    let Some(stored_fingerprint) = stored_fingerprint else {
        return Ok(());
    };

    if stored_fingerprint.model != desired_model {
        return Err(SurfaceError::ReindexRequired(format!(
            "stored embedding model is {}, current model is {desired_model}",
            stored_fingerprint.model
        )));
    }
    if stored_fingerprint.dimension != desired_dimension {
        return Err(SurfaceError::ReindexRequired(format!(
            "stored embedding dimension is {}, current dimension is {desired_dimension}",
            stored_fingerprint.dimension
        )));
    }
    if stored_fingerprint.vector_schema != EMBEDDING_VECTOR_SCHEMA {
        return Err(SurfaceError::ReindexRequired(format!(
            "stored vector schema is {}, expected {EMBEDDING_VECTOR_SCHEMA}",
            stored_fingerprint.vector_schema
        )));
    }

    Ok(())
}

pub(crate) async fn validate_read_only_vector_store(
    db: &PgPool,
    vector_store: &dyn VectorRepository,
    embedding: &dyn EmbeddingProvider,
) -> Result<(), SurfaceError> {
    let desired_dimension = embedding.dimension();
    let desired_model = embedding.model_name();
    let current_dimension = vector_store.collection_dimension().await.map_err(|e| {
        SurfaceError::Configuration(format!("inspect vector collection dimension: {e}"))
    })?;
    let stored_fingerprint = load_embedding_fingerprint(db)
        .await
        .map_err(|e| SurfaceError::Configuration(format!("load embedding fingerprint: {e}")))?;

    validate_read_only_collection_state(
        current_dimension,
        desired_dimension,
        desired_model,
        stored_fingerprint.as_ref(),
    )
}

pub(crate) fn build_reranker(settings: &Settings) -> Option<SharedReranker> {
    let rerank = settings.rerank();
    if !rerank.enabled {
        return None;
    }

    let endpoint = env::var("ANKIATLAS_RERANK_ENDPOINT")
        .ok()
        .filter(|value| !value.is_empty());
    let endpoint = match endpoint {
        Some(endpoint) => endpoint,
        None => {
            tracing::warn!(
                "reranking enabled in settings but ANKIATLAS_RERANK_ENDPOINT is not set; disabling reranker"
            );
            return None;
        }
    };

    Some(Arc::new(CrossEncoderReranker::new(
        rerank.model,
        rerank.batch_size as usize,
        endpoint,
    )))
}

/// Configuration for building surface services from explicit values (no env var reads).
/// Used by the FFI bridge where config comes from the Swift UI.
#[derive(Debug, Clone)]
pub struct BridgeServicesConfig {
    pub postgres_url: String,
    pub embedding_provider: EmbeddingProviderKind,
    pub embedding_model: String,
    pub embedding_dimension: usize,
    pub embedding_api_key: Option<String>,
}

/// Build surface services from explicit configuration (used by FFI bridge).
///
/// Unlike `build_surface_services`, this does not read environment variables
/// for API keys -- all values come from the provided config.
pub async fn build_surface_services_from_bridge_config(
    config: &BridgeServicesConfig,
) -> Result<SurfaceServices, SurfaceError> {
    let db = create_pool(&common::config::DatabaseSettings {
        postgres_url: config.postgres_url.clone(),
    })
    .await?;

    let embedding_config = match config.embedding_provider {
        EmbeddingProviderKind::Mock => EmbeddingProviderConfig::Mock {
            dimension: config.embedding_dimension,
        },
        EmbeddingProviderKind::OpenAi => {
            let api_key = config.embedding_api_key.clone().ok_or_else(|| {
                SurfaceError::Configuration("API key required for OpenAI provider".into())
            })?;
            EmbeddingProviderConfig::OpenAi {
                model: config.embedding_model.clone(),
                dimension: config.embedding_dimension,
                batch_size: None,
                api_key,
            }
        }
        EmbeddingProviderKind::Google => {
            let api_key = config.embedding_api_key.clone().ok_or_else(|| {
                SurfaceError::Configuration("API key required for Google provider".into())
            })?;
            EmbeddingProviderConfig::Google {
                model: config.embedding_model.clone(),
                dimension: config.embedding_dimension,
                batch_size: None,
                api_key,
            }
        }
        EmbeddingProviderKind::FastEmbed => {
            return Err(SurfaceError::Configuration(
                "FastEmbed provider requires the 'local-embeddings' feature".into(),
            ));
        }
    };

    let embedding: SharedEmbeddingProvider = Arc::from(
        create_embedding_provider(&embedding_config).map_err(|e| {
            SurfaceError::Configuration(format!("create embedding provider: {e}"))
        })?,
    );

    let vector_store = Arc::new(PgVectorRepository::new(db.clone()));
    let vector_repo = vector_store as SharedVectorRepository;

    let search = Arc::new(SearchFacadeImpl {
        inner: SearchService::new(
            embedding.clone(),
            vector_repo.clone(),
            None::<SharedReranker>,
            Arc::new(SqlxSearchReadRepository::new(db.clone())),
            false,
            50,
        ),
    }) as Arc<dyn crate::SearchFacade>;

    let analytics = Arc::new(AnalyticsFacadeImpl {
        inner: AnalyticsService::new(
            embedding,
            vector_repo,
            Arc::new(SqlxAnalyticsRepository::new(db.clone())),
        ),
    }) as Arc<dyn crate::AnalyticsFacade>;

    let job_manager = Arc::new(NoopBridgeJobManager) as Arc<dyn JobManager>;
    Ok(SurfaceServices::new(db, job_manager, search, analytics))
}

/// Minimal job manager for bridge mode (no background job queue).
struct NoopBridgeJobManager;

#[async_trait::async_trait]
impl JobManager for NoopBridgeJobManager {
    async fn enqueue_sync_job(
        &self,
        _payload: jobs::SyncJobPayload,
        _run_at: Option<chrono::DateTime<chrono::Utc>>,
    ) -> Result<jobs::JobRecord, jobs::JobError> {
        Err(jobs::JobError::Unsupported(
            "job queue not available in bridge mode".to_string(),
        ))
    }

    async fn enqueue_index_job(
        &self,
        _payload: jobs::IndexJobPayload,
        _run_at: Option<chrono::DateTime<chrono::Utc>>,
    ) -> Result<jobs::JobRecord, jobs::JobError> {
        Err(jobs::JobError::Unsupported(
            "job queue not available in bridge mode".to_string(),
        ))
    }

    async fn get_job(&self, _job_id: &str) -> Result<jobs::JobRecord, jobs::JobError> {
        Err(jobs::JobError::Unsupported(
            "job queue not available in bridge mode".to_string(),
        ))
    }

    async fn cancel_job(&self, _job_id: &str) -> Result<jobs::JobRecord, jobs::JobError> {
        Err(jobs::JobError::Unsupported(
            "job queue not available in bridge mode".to_string(),
        ))
    }

    async fn close(&self) -> Result<(), jobs::JobError> {
        Ok(())
    }
}

pub async fn build_surface_services(
    settings: &Settings,
    options: BuildSurfaceServicesOptions,
) -> Result<SurfaceServices, SurfaceError> {
    let db = create_pool(&settings.database()).await?;
    let embedding: SharedEmbeddingProvider = Arc::from(
        create_embedding_provider(&build_embedding_config(settings)?).map_err(|e| {
            SurfaceError::Configuration(format!(
                "create embedding provider for surface runtime: {e}"
            ))
        })?,
    );
    let vector_store = Arc::new(PgVectorRepository::new(db.clone()));
    if !options.enable_direct_execution {
        validate_read_only_vector_store(&db, vector_store.as_ref(), embedding.as_ref()).await?;
    }
    let vector_repo = vector_store as SharedVectorRepository;
    let reranker = build_reranker(settings);
    let rerank_enabled = settings.rerank().enabled && reranker.is_some();

    let search = Arc::new(SearchFacadeImpl {
        inner: SearchService::new(
            embedding.clone(),
            vector_repo.clone(),
            reranker,
            Arc::new(SqlxSearchReadRepository::new(db.clone())),
            rerank_enabled,
            settings.rerank().top_n as usize,
        ),
    }) as Arc<dyn crate::service_facades::SearchFacade>;

    let analytics = Arc::new(AnalyticsFacadeImpl {
        inner: AnalyticsService::new(
            embedding.clone(),
            vector_repo.clone(),
            Arc::new(SqlxAnalyticsRepository::new(db.clone())),
        ),
    }) as Arc<dyn crate::service_facades::AnalyticsFacade>;

    let job_settings = settings.jobs();
    let job_manager = Arc::new(
        PgJobManager::new(
            db.clone(),
            job_settings.max_retries,
            u64::from(job_settings.result_ttl_seconds),
        )
        .await
        .map_err(|e| {
            SurfaceError::Configuration(format!(
                "create PostgreSQL job manager for surface runtime: {e}"
            ))
        })?,
    ) as Arc<dyn JobManager>;

    let mut services = SurfaceServices::new(db.clone(), job_manager, search, analytics);
    if options.enable_direct_execution {
        let index = Arc::new(IndexingService::new(
            db.clone(),
            embedding,
            vector_repo,
            settings.anki_collection_path.as_ref().map(PathBuf::from),
            settings.anki_media_root.as_ref().map(PathBuf::from),
        ));
        services.sync = Arc::new(SyncExecutionService::new(db, index.clone()));
        services.index = index;
        services.direct_execution_enabled = true;
    }

    Ok(services)
}
