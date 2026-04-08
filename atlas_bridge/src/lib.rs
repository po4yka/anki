// This crate is a C-ABI FFI bridge. It inherently requires unsafe code for raw
// pointer handling and #[no_mangle] exports. The functions are not marked unsafe
// because they are called from Swift/C which has no concept of Rust's unsafe.
#![allow(unsafe_code)]
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::{CStr, c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::slice;
use std::sync::Arc;

use jobs::{IndexJobPayload, JobError, JobManager, JobRecord, SyncJobPayload};
use serde::Deserialize;
use surface_contracts::analytics::{
    DuplicateCluster, DuplicateStats, LabelingStats, TaxonomyLoadSummary, TopicCoverage, TopicGap,
    WeakNote,
};
use surface_contracts::search::{
    ChunkSearchRequest, ChunkSearchResponse, SearchRequest, SearchResponse,
};
use surface_runtime::{AnalyticsFacade, SearchFacade, SurfaceError, SurfaceServices};
use tokio::runtime::Runtime;

/// Byte buffer for transferring owned data across the FFI boundary.
/// Swift must call atlas_free_buffer() when it is done with the data.
#[repr(C)]
pub struct AtlasByteBuffer {
    data: *mut u8,
    len: usize,
}

impl AtlasByteBuffer {
    fn from_vec(v: Vec<u8>) -> Self {
        let mut v = v.into_boxed_slice();
        let buf = AtlasByteBuffer {
            data: v.as_mut_ptr(),
            len: v.len(),
        };
        std::mem::forget(v);
        buf
    }

    fn from_str(s: &str) -> Self {
        Self::from_vec(s.as_bytes().to_vec())
    }

    #[allow(dead_code)]
    fn empty() -> Self {
        AtlasByteBuffer {
            data: std::ptr::null_mut(),
            len: 0,
        }
    }
}

/// Configuration passed from Swift as a JSON blob.
#[derive(Debug, Deserialize, Default)]
pub struct AtlasConfig {
    pub postgres_url: Option<String>,
    pub qdrant_url: Option<String>,
    pub embedding_provider: Option<String>,
    pub embedding_model: Option<String>,
    pub embedding_dimension: Option<u32>,
    pub embedding_api_key: Option<String>,
}

/// No-op job manager used when no PostgreSQL backend is configured.
struct NoopJobManager;

#[async_trait::async_trait]
impl JobManager for NoopJobManager {
    async fn enqueue_sync_job(
        &self,
        _payload: SyncJobPayload,
        _run_at: Option<chrono::DateTime<chrono::Utc>>,
    ) -> Result<JobRecord, JobError> {
        Err(JobError::Unsupported(
            "job manager not configured".to_string(),
        ))
    }

    async fn enqueue_index_job(
        &self,
        _payload: IndexJobPayload,
        _run_at: Option<chrono::DateTime<chrono::Utc>>,
    ) -> Result<JobRecord, JobError> {
        Err(JobError::Unsupported(
            "job manager not configured".to_string(),
        ))
    }

    async fn get_job(&self, _job_id: &str) -> Result<JobRecord, JobError> {
        Err(JobError::Unsupported(
            "job manager not configured".to_string(),
        ))
    }

    async fn cancel_job(&self, _job_id: &str) -> Result<JobRecord, JobError> {
        Err(JobError::Unsupported(
            "job manager not configured".to_string(),
        ))
    }

    async fn close(&self) -> Result<(), JobError> {
        Ok(())
    }
}

/// No-op search facade used when no backend is configured.
struct NoopSearch;

#[async_trait::async_trait]
impl SearchFacade for NoopSearch {
    async fn search(&self, _request: &SearchRequest) -> Result<SearchResponse, SurfaceError> {
        Err(SurfaceError::Configuration(
            "search not configured: provide postgres_url and qdrant_url in AtlasConfig".to_string(),
        ))
    }

    async fn search_chunks(
        &self,
        _request: &ChunkSearchRequest,
    ) -> Result<ChunkSearchResponse, SurfaceError> {
        Err(SurfaceError::Configuration(
            "search not configured: provide postgres_url and qdrant_url in AtlasConfig".to_string(),
        ))
    }
}

/// No-op analytics facade used when no backend is configured.
struct NoopAnalytics;

#[async_trait::async_trait]
impl AnalyticsFacade for NoopAnalytics {
    async fn load_taxonomy(
        &self,
        _yaml_path: Option<PathBuf>,
    ) -> Result<TaxonomyLoadSummary, SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn label_notes(
        &self,
        _yaml_path: Option<PathBuf>,
        _min_confidence: f32,
    ) -> Result<LabelingStats, SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn get_taxonomy_tree(
        &self,
        _root_path: Option<String>,
    ) -> Result<Vec<serde_json::Value>, SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn get_coverage(
        &self,
        _topic_path: String,
        _include_subtree: bool,
    ) -> Result<Option<TopicCoverage>, SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn get_gaps(
        &self,
        _topic_path: String,
        _min_coverage: i64,
    ) -> Result<Vec<TopicGap>, SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn get_weak_notes(
        &self,
        _topic_path: String,
        _max_results: i64,
    ) -> Result<Vec<WeakNote>, SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }

    async fn find_duplicates(
        &self,
        _threshold: f64,
        _max_clusters: usize,
        _deck_filter: Option<Vec<String>>,
        _tag_filter: Option<Vec<String>>,
    ) -> Result<(Vec<DuplicateCluster>, DuplicateStats), SurfaceError> {
        Err(SurfaceError::Configuration(
            "analytics not configured: provide postgres_url in AtlasConfig".to_string(),
        ))
    }
}

/// Opaque handle holding real SurfaceServices and a tokio Runtime.
pub struct AtlasHandle {
    services: Arc<SurfaceServices>,
    runtime: Runtime,
}

/// Build SurfaceServices from an AtlasConfig using noop facades (no DB/vector store).
fn build_noop_services(postgres_url: Option<&str>) -> Result<SurfaceServices, String> {
    let url = postgres_url.unwrap_or("postgres://localhost/anki_atlas");
    let pool = sqlx::postgres::PgPoolOptions::new()
        .connect_lazy(url)
        .map_err(|e| format!("failed to create lazy postgres pool: {e}"))?;
    Ok(SurfaceServices::new(
        pool,
        Arc::new(NoopJobManager),
        Arc::new(NoopSearch),
        Arc::new(NoopAnalytics),
    ))
}

/// Initialize an Atlas handle from a JSON-encoded AtlasConfig.
///
/// Returns an opaque pointer on success. The caller must pass this pointer to
/// all subsequent atlas_command calls and must call atlas_free() when done.
/// Returns null on error or if a panic occurs.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_init(config_data: *const u8, config_len: usize) -> *mut c_void {
    catch_unwind(|| {
        let config: AtlasConfig = if config_data.is_null() || config_len == 0 {
            AtlasConfig::default()
        } else {
            // SAFETY: `config_data` points to `config_len` bytes owned by the Swift caller.
            // The caller guarantees the pointer is valid for the duration of this call.
            let bytes = unsafe { slice::from_raw_parts(config_data, config_len) };
            serde_json::from_slice(bytes).unwrap_or_default()
        };

        let Ok(runtime) = Runtime::new() else {
            return std::ptr::null_mut();
        };

        let Ok(services) = build_noop_services(config.postgres_url.as_deref()) else {
            return std::ptr::null_mut();
        };

        let handle = Box::new(AtlasHandle {
            services: Arc::new(services),
            runtime,
        });
        Box::into_raw(handle) as *mut c_void
    })
    .unwrap_or(std::ptr::null_mut())
}

fn dispatch_command(handle: &AtlasHandle, method: &str, input: &[u8]) -> Result<Vec<u8>, String> {
    match method {
        "search" => {
            let request: SearchRequest = serde_json::from_slice(input)
                .map_err(|e| format!("invalid search request: {e}"))?;
            let response = handle
                .runtime
                .block_on(handle.services.search.search(&request))
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&response).map_err(|e| e.to_string())
        }
        "search_chunks" => {
            let request: ChunkSearchRequest = serde_json::from_slice(input)
                .map_err(|e| format!("invalid chunk search request: {e}"))?;
            let response = handle
                .runtime
                .block_on(handle.services.search.search_chunks(&request))
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&response).map_err(|e| e.to_string())
        }
        "get_taxonomy_tree" => {
            #[derive(Deserialize, Default)]
            struct Input {
                root_path: Option<String>,
            }
            let req: Input = serde_json::from_slice(input).unwrap_or_default();
            let response = handle
                .runtime
                .block_on(handle.services.analytics.get_taxonomy_tree(req.root_path))
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&response).map_err(|e| e.to_string())
        }
        "get_coverage" => {
            #[derive(Deserialize)]
            struct Input {
                topic_path: String,
                #[serde(default)]
                include_subtree: bool,
            }
            let req: Input = serde_json::from_slice(input)
                .map_err(|e| format!("invalid get_coverage request: {e}"))?;
            let response = handle
                .runtime
                .block_on(
                    handle
                        .services
                        .analytics
                        .get_coverage(req.topic_path, req.include_subtree),
                )
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&response).map_err(|e| e.to_string())
        }
        "get_gaps" => {
            #[derive(Deserialize)]
            struct Input {
                topic_path: String,
                #[serde(default)]
                min_coverage: i64,
            }
            let req: Input = serde_json::from_slice(input)
                .map_err(|e| format!("invalid get_gaps request: {e}"))?;
            let response = handle
                .runtime
                .block_on(
                    handle
                        .services
                        .analytics
                        .get_gaps(req.topic_path, req.min_coverage),
                )
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&response).map_err(|e| e.to_string())
        }
        "get_weak_notes" => {
            #[derive(Deserialize)]
            struct Input {
                topic_path: String,
                #[serde(default = "default_max_results")]
                max_results: i64,
            }
            fn default_max_results() -> i64 {
                20
            }
            let req: Input = serde_json::from_slice(input)
                .map_err(|e| format!("invalid get_weak_notes request: {e}"))?;
            let response = handle
                .runtime
                .block_on(
                    handle
                        .services
                        .analytics
                        .get_weak_notes(req.topic_path, req.max_results),
                )
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&response).map_err(|e| e.to_string())
        }
        "find_duplicates" => {
            #[derive(Deserialize)]
            struct Input {
                #[serde(default = "default_threshold")]
                threshold: f64,
                #[serde(default = "default_max_clusters")]
                max_clusters: usize,
                deck_filter: Option<Vec<String>>,
                tag_filter: Option<Vec<String>>,
            }
            fn default_threshold() -> f64 {
                0.95
            }
            fn default_max_clusters() -> usize {
                50
            }
            let req: Input = serde_json::from_slice(input).unwrap_or(Input {
                threshold: default_threshold(),
                max_clusters: default_max_clusters(),
                deck_filter: None,
                tag_filter: None,
            });
            let (clusters, stats) = handle
                .runtime
                .block_on(handle.services.analytics.find_duplicates(
                    req.threshold,
                    req.max_clusters,
                    req.deck_filter,
                    req.tag_filter,
                ))
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&serde_json::json!({ "clusters": clusters, "stats": stats }))
                .map_err(|e| e.to_string())
        }
        "generate_preview" => {
            #[derive(Deserialize)]
            struct Input {
                file_path: String,
            }
            let req: Input = serde_json::from_slice(input)
                .map_err(|e| format!("invalid generate_preview request: {e}"))?;
            let preview = handle
                .services
                .generate_preview
                .preview(PathBuf::from(&req.file_path).as_path())
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&preview).map_err(|e| e.to_string())
        }
        "obsidian_scan" => {
            #[derive(Deserialize)]
            struct Input {
                vault_path: String,
                #[serde(default)]
                source_dirs: Vec<String>,
            }
            let req: Input = serde_json::from_slice(input)
                .map_err(|e| format!("invalid obsidian_scan request: {e}"))?;
            let preview = handle
                .services
                .obsidian_scan
                .scan(
                    PathBuf::from(&req.vault_path).as_path(),
                    &req.source_dirs,
                    common::ExecutionMode::DryRun,
                )
                .map_err(|e| e.to_string())?;
            serde_json::to_vec(&preview).map_err(|e| e.to_string())
        }
        _ => Err(format!("unknown atlas method: {method}")),
    }
}

/// Dispatch a JSON method call to Atlas services.
///
/// On success, is_error is set to false and the returned AtlasByteBuffer contains
/// the JSON-encoded response. On error, is_error is set to true and the returned
/// AtlasByteBuffer contains an error message string.
///
/// The returned AtlasByteBuffer must be freed with atlas_free_buffer().
#[unsafe(no_mangle)]
pub extern "C" fn atlas_command(
    handle: *mut c_void,
    method: *const c_char,
    input: *const u8,
    input_len: usize,
    is_error: *mut bool,
) -> AtlasByteBuffer {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
            unsafe { *is_error = true };
            return AtlasByteBuffer::from_str("atlas handle is null");
        }

        // SAFETY: `method` is a valid null-terminated C string provided by the Swift caller.
        let Ok(method_str) = (unsafe { CStr::from_ptr(method).to_str() }) else {
            // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
            unsafe { *is_error = true };
            return AtlasByteBuffer::from_str("invalid UTF-8 in method name");
        };

        let input_bytes: &[u8] = if input.is_null() || input_len == 0 {
            b"{}"
        } else {
            // SAFETY: `input` points to `input_len` bytes owned by the Swift caller.
            // The caller guarantees the pointer is valid for the duration of this call.
            unsafe { slice::from_raw_parts(input, input_len) }
        };

        // SAFETY: `handle` was created by `atlas_init` via `Box::into_raw` and has not been freed.
        // The caller guarantees exclusive access.
        let handle_ref = unsafe { &*(handle as *const AtlasHandle) };

        match dispatch_command(handle_ref, method_str, input_bytes) {
            Ok(bytes) => {
                // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
                unsafe { *is_error = false };
                AtlasByteBuffer::from_vec(bytes)
            }
            Err(msg) => {
                // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
                unsafe { *is_error = true };
                AtlasByteBuffer::from_str(&msg)
            }
        }
    }));
    match result {
        Ok(buf) => buf,
        Err(_) => {
            // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
            unsafe { *is_error = true };
            AtlasByteBuffer::from_str("internal panic in atlas_command")
        }
    }
}

/// Free an AtlasHandle instance created by atlas_init.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_free(handle: *mut c_void) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !handle.is_null() {
            // SAFETY: `handle` was created by `atlas_init` via `Box::into_raw`.
            // The caller guarantees this is the final use of this pointer.
            unsafe { drop(Box::from_raw(handle as *mut AtlasHandle)) };
        }
    }));
}

/// Free an AtlasByteBuffer returned by atlas_command.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_free_buffer(buf: AtlasByteBuffer) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !buf.data.is_null() {
            // SAFETY: `buf.data` and `buf.len` were produced by `AtlasByteBuffer::from_vec`.
            // The caller guarantees this buffer has not already been freed.
            unsafe {
                drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                    buf.data, buf.len,
                )));
            };
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_with_null_config() {
        let ptr = atlas_init(std::ptr::null(), 0);
        if !ptr.is_null() {
            atlas_free(ptr);
        }
    }

    #[test]
    fn init_with_empty_json() {
        let json = b"{}";
        let ptr = atlas_init(json.as_ptr(), json.len());
        if !ptr.is_null() {
            atlas_free(ptr);
        }
    }

    #[test]
    fn init_with_invalid_json_falls_back() {
        let garbage = b"not json at all";
        let ptr = atlas_init(garbage.as_ptr(), garbage.len());
        if !ptr.is_null() {
            atlas_free(ptr);
        }
    }

    #[test]
    fn free_null_does_not_crash() {
        atlas_free(std::ptr::null_mut());
    }

    #[test]
    fn free_buffer_null_data_does_not_crash() {
        atlas_free_buffer(AtlasByteBuffer::empty());
    }

    #[test]
    fn free_buffer_valid_data_does_not_crash() {
        atlas_free_buffer(AtlasByteBuffer::from_vec(vec![1u8, 2, 3]));
    }
}
