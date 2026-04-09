use sqlx::PgPool;

use crate::error::JobError;
use crate::types::{IndexJobPayload, IndexJobResult, SyncJobPayload, SyncJobResult};

/// Task execution context for one job attempt.
#[derive(Debug, Clone)]
pub struct TaskContext {
    pub attempt: u32,
    pub pool: PgPool,
}

/// Background task: sync Anki collection and optionally index vectors.
pub async fn job_sync(
    ctx: &TaskContext,
    _job_id: &str,
    payload: &SyncJobPayload,
) -> Result<SyncJobResult, JobError> {
    let sync_service = anki_sync::core::SyncService::new(ctx.pool.clone());
    let stats = sync_service
        .sync_collection(&payload.source)
        .await
        .map_err(|e| JobError::TaskExecution(format!("sync failed: {e}")))?;
    Ok(SyncJobResult {
        decks_upserted: stats.decks_upserted as i64,
        models_upserted: stats.models_upserted as i64,
        notes_upserted: stats.notes_upserted as i64,
        notes_deleted: stats.notes_deleted as i64,
        cards_upserted: stats.cards_upserted as i64,
        card_stats_upserted: stats.card_stats_upserted as i64,
        duration_ms: stats.duration_ms,
        notes_embedded: None,
        notes_skipped: None,
        index_errors: Vec::new(),
    })
}

/// Background task: index notes to vector store.
///
/// Full indexing requires surface-runtime context (embedding provider, vector repo).
/// Use direct execution mode until surface-runtime is available in job context.
pub async fn job_index(
    _ctx: &TaskContext,
    _job_id: &str,
    _payload: &IndexJobPayload,
) -> Result<IndexJobResult, JobError> {
    Err(JobError::Unsupported(
        "index job requires surface-runtime context; use direct execution mode instead".to_string(),
    ))
}
