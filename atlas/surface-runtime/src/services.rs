use std::sync::Arc;

use jobs::JobManager;
use sqlx::PgPool;

use crate::workflows::{
    GeneratePreviewService, IndexExecutor, IndexingService, ObsidianScanService,
    SyncExecutionService, TagAuditService, ValidationService,
};

pub use crate::service_facades::{AnalyticsFacade, SearchFacade};
pub use crate::services_builder::{
    BridgeServicesConfig, BuildSurfaceServicesOptions, EmbeddingFingerprint,
    build_surface_services, build_surface_services_from_bridge_config,
};

pub struct SurfaceServices {
    pub db: PgPool,
    pub job_manager: Arc<dyn JobManager>,
    pub search: Arc<dyn SearchFacade>,
    pub analytics: Arc<dyn AnalyticsFacade>,
    pub sync: Arc<SyncExecutionService>,
    pub index: Arc<dyn IndexExecutor>,
    pub generate_preview: Arc<GeneratePreviewService>,
    pub validation: Arc<ValidationService>,
    pub obsidian_scan: Arc<ObsidianScanService>,
    pub tag_audit: Arc<TagAuditService>,
    pub(crate) direct_execution_enabled: bool,
}

impl SurfaceServices {
    pub fn new(
        db: PgPool,
        job_manager: Arc<dyn JobManager>,
        search: Arc<dyn SearchFacade>,
        analytics: Arc<dyn AnalyticsFacade>,
    ) -> Self {
        Self {
            sync: Arc::new(SyncExecutionService::unsupported(db.clone())),
            index: Arc::new(IndexingService::unsupported(db.clone())),
            generate_preview: Arc::new(GeneratePreviewService::new()),
            validation: Arc::new(ValidationService::new()),
            obsidian_scan: Arc::new(ObsidianScanService::new()),
            tag_audit: Arc::new(TagAuditService::new()),
            direct_execution_enabled: false,
            db,
            job_manager,
            search,
            analytics,
        }
    }

    #[cfg(test)]
    pub(crate) fn direct_execution_enabled(&self) -> bool {
        self.direct_execution_enabled
    }
}

#[cfg(test)]
mod tests {
    use super::{AnalyticsFacade, SearchFacade, SurfaceServices};
    use crate::service_facades::{MockAnalyticsFacade, MockSearchFacade};
    use crate::services_builder::{
        EMBEDDING_VECTOR_SCHEMA, EmbeddingFingerprint, validate_read_only_collection_state,
    };
    use jobs::JobManager;
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;

    struct NoopJobManager;

    #[async_trait::async_trait]
    impl JobManager for NoopJobManager {
        async fn enqueue_sync_job(
            &self,
            _payload: jobs::types::SyncJobPayload,
            _run_at: Option<chrono::DateTime<chrono::Utc>>,
        ) -> Result<jobs::types::JobRecord, jobs::JobError> {
            unreachable!("job manager is not exercised in this test")
        }

        async fn enqueue_index_job(
            &self,
            _payload: jobs::types::IndexJobPayload,
            _run_at: Option<chrono::DateTime<chrono::Utc>>,
        ) -> Result<jobs::types::JobRecord, jobs::JobError> {
            unreachable!("job manager is not exercised in this test")
        }

        async fn get_job(&self, _job_id: &str) -> Result<jobs::types::JobRecord, jobs::JobError> {
            unreachable!("job manager is not exercised in this test")
        }

        async fn cancel_job(
            &self,
            _job_id: &str,
        ) -> Result<jobs::types::JobRecord, jobs::JobError> {
            unreachable!("job manager is not exercised in this test")
        }

        async fn close(&self) -> Result<(), jobs::JobError> {
            Ok(())
        }
    }

    #[test]
    fn fresh_runtime_allows_missing_collection_without_fingerprint() {
        let result = validate_read_only_collection_state(None, 384, "mock/test", None);
        assert!(result.is_ok());
    }

    #[test]
    fn missing_collection_requires_reindex_when_fingerprint_exists() {
        let result = validate_read_only_collection_state(
            None,
            384,
            "mock/test",
            Some(&EmbeddingFingerprint {
                model: "mock/test".to_string(),
                dimension: 384,
                vector_schema: EMBEDDING_VECTOR_SCHEMA.to_string(),
            }),
        );

        let error = result.expect_err("missing indexed collection should fail");
        assert_eq!(
            error.to_string(),
            "reindex required: vector collection is missing"
        );
    }

    #[tokio::test]
    async fn surface_services_new_keeps_direct_execution_disabled_by_default() {
        let db = PgPoolOptions::new()
            .connect_lazy("postgres://localhost/anki_atlas")
            .expect("lazy postgres pool");
        let search = Arc::new(MockSearchFacade::new()) as Arc<dyn SearchFacade>;
        let analytics = Arc::new(MockAnalyticsFacade::new()) as Arc<dyn AnalyticsFacade>;
        let services = SurfaceServices::new(
            db,
            Arc::new(NoopJobManager) as Arc<dyn JobManager>,
            search,
            analytics,
        );

        assert!(!services.direct_execution_enabled());
    }
}
