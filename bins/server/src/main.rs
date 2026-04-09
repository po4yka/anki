use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use common::config::Settings;
use serde::Deserialize;
use serde_json::Value;
use surface_runtime::{BuildSurfaceServicesOptions, SurfaceServices, build_surface_services};
use tower_http::cors::CorsLayer;
use tracing::info;

type AppState = Arc<SurfaceServices>;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt::init();

    let settings = Settings::load().map_err(|e| anyhow::anyhow!("{e}"))?;

    let api = settings.api();
    let addr: SocketAddr = format!("{}:{}", api.host, api.port)
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([0, 0, 0, 0], api.port)));

    info!("building surface services...");
    let services = build_surface_services(
        &settings,
        BuildSurfaceServicesOptions {
            enable_direct_execution: true,
        },
    )
    .await
    .map_err(|e| anyhow::anyhow!("failed to build services: {e}"))?;

    let state: AppState = Arc::new(services);

    let app = Router::new()
        .route("/api/search", post(handle_search))
        .route("/api/search_chunks", post(handle_search_chunks))
        .route("/api/get_taxonomy_tree", post(handle_taxonomy_tree))
        .route("/api/get_coverage", post(handle_coverage))
        .route("/api/get_gaps", post(handle_gaps))
        .route("/api/get_weak_notes", post(handle_weak_notes))
        .route("/api/find_duplicates", post(handle_duplicates))
        .route("/api/generate_preview", post(handle_generate_preview))
        .route("/api/obsidian_scan", post(handle_obsidian_scan))
        .route("/health", get(handle_health))
        .layer(CorsLayer::permissive())
        .with_state(state);

    info!("atlas server listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn handle_health() -> &'static str {
    "ok"
}

struct AppError(StatusCode, String);

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let body = serde_json::json!({ "error": self.1 });
        (self.0, Json(body)).into_response()
    }
}

impl AppError {
    fn internal(e: impl std::fmt::Display) -> Self {
        Self(StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    }

    fn bad_request(e: impl std::fmt::Display) -> Self {
        Self(StatusCode::BAD_REQUEST, e.to_string())
    }
}

async fn handle_search(
    State(services): State<AppState>,
    Json(request): Json<surface_contracts::search::SearchRequest>,
) -> Result<Json<Value>, AppError> {
    let result = services
        .search
        .search(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(Json)
        .map_err(AppError::internal)
}

async fn handle_search_chunks(
    State(services): State<AppState>,
    Json(request): Json<surface_contracts::search::ChunkSearchRequest>,
) -> Result<Json<Value>, AppError> {
    let result = services
        .search
        .search_chunks(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize, Default)]
struct TaxonomyTreeInput {
    root_path: Option<String>,
}

async fn handle_taxonomy_tree(
    State(services): State<AppState>,
    Json(input): Json<TaxonomyTreeInput>,
) -> Result<Json<Value>, AppError> {
    let result = services
        .analytics
        .get_taxonomy_tree(input.root_path)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct CoverageInput {
    topic_path: String,
    #[serde(default)]
    include_subtree: bool,
}

async fn handle_coverage(
    State(services): State<AppState>,
    Json(input): Json<CoverageInput>,
) -> Result<Json<Value>, AppError> {
    let result = services
        .analytics
        .get_coverage(input.topic_path, input.include_subtree)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct GapsInput {
    topic_path: String,
    #[serde(default)]
    min_coverage: i64,
}

async fn handle_gaps(
    State(services): State<AppState>,
    Json(input): Json<GapsInput>,
) -> Result<Json<Value>, AppError> {
    let result = services
        .analytics
        .get_gaps(input.topic_path, input.min_coverage)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct WeakNotesInput {
    topic_path: String,
    #[serde(default = "default_max_results")]
    max_results: i64,
}

fn default_max_results() -> i64 {
    20
}

async fn handle_weak_notes(
    State(services): State<AppState>,
    Json(input): Json<WeakNotesInput>,
) -> Result<Json<Value>, AppError> {
    let result = services
        .analytics
        .get_weak_notes(input.topic_path, input.max_results)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct DuplicatesInput {
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

async fn handle_duplicates(
    State(services): State<AppState>,
    Json(input): Json<DuplicatesInput>,
) -> Result<Json<Value>, AppError> {
    let (clusters, stats) = services
        .analytics
        .find_duplicates(
            input.threshold,
            input.max_clusters,
            input.deck_filter,
            input.tag_filter,
        )
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(serde_json::json!({ "clusters": clusters, "stats": stats }))
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct GeneratePreviewInput {
    file_path: String,
}

async fn handle_generate_preview(
    State(services): State<AppState>,
    Json(input): Json<GeneratePreviewInput>,
) -> Result<Json<Value>, AppError> {
    let preview = services
        .generate_preview
        .preview(PathBuf::from(&input.file_path).as_path())
        .map_err(AppError::bad_request)?;
    serde_json::to_value(preview)
        .map(Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct ObsidianScanInput {
    vault_path: String,
    #[serde(default)]
    source_dirs: Vec<String>,
}

async fn handle_obsidian_scan(
    State(services): State<AppState>,
    Json(input): Json<ObsidianScanInput>,
) -> Result<Json<Value>, AppError> {
    let preview = services
        .obsidian_scan
        .scan(
            PathBuf::from(&input.vault_path).as_path(),
            &input.source_dirs,
            common::ExecutionMode::DryRun,
        )
        .map_err(AppError::bad_request)?;
    serde_json::to_value(preview)
        .map(Json)
        .map_err(AppError::internal)
}
