use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    Router,
    body::{Body, Bytes},
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use common::config::{ApiDeploymentKind, Settings};
use database::{create_pool, run_migrations};
use if_addrs::{IfAddr, get_if_addrs};
use mdns_sd::{ServiceDaemon, ServiceInfo};
mod remote_sessions;
use remote_sessions::{AuthSessionRecord, SessionManager};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use surface_contracts::knowledge_graph::{
    NoteLinksRequest, RefreshKnowledgeGraphRequest, TopicNeighborhoodRequest,
};
use surface_runtime::{BuildSurfaceServicesOptions, SurfaceServices, build_surface_services};
use tower_http::cors::CorsLayer;
use tracing::{info, warn};
use uuid::Uuid;

type SurfaceState = Arc<SurfaceServices>;
type SharedState = Arc<ServerState>;

const BACKEND_SESSION_HEADER: &str = "x-anki-backend-session";
const BACKEND_ERROR_HEADER: &str = "x-anki-error";
const COMPANION_SERVICE_TYPE: &str = "_anki-atlas._tcp.local.";
const COMPANION_SERVICE_KIND: &str = "_anki-atlas._tcp";

#[derive(Clone)]
struct ServerState {
    surface: Option<SurfaceState>,
    sessions: Arc<SessionManager>,
    deployment_kind: DeploymentKind,
    pairing_api_key: Option<String>,
    pairing_account: AccountResponse,
}

#[derive(Clone, Serialize, Deserialize)]
struct AccountResponse {
    account_id: String,
    account_display_name: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct CapabilitiesResponse {
    supports_remote_anki: bool,
    supports_atlas: bool,
    deployment_kind: DeploymentKind,
    execution_mode: ExecutionMode,
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum DeploymentKind {
    Companion,
    Cloud,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ExecutionMode {
    Remote,
    Unavailable,
}

#[derive(Clone, Serialize, Deserialize)]
struct PairingCodeResponse {
    pairing_code: String,
    pairing_url: String,
    expires_at: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct AuthSessionResponse {
    access_token: String,
    refresh_token: String,
    expires_at: String,
    account_id: String,
    account_display_name: String,
    capabilities: CapabilitiesResponse,
}

#[derive(Clone, Serialize, Deserialize)]
struct BackendSessionInitResponse {
    backend_session_id: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct MeResponse {
    account: AccountResponse,
    capabilities: CapabilitiesResponse,
}

#[derive(Deserialize)]
struct PairingCreateInput {
    device_name: Option<String>,
}

#[derive(Deserialize)]
struct PairingExchangeInput {
    pairing_code: String,
}

#[derive(Deserialize)]
struct RefreshInput {
    refresh_token: String,
}

#[derive(Deserialize)]
struct LogoutInput {
    refresh_token: Option<String>,
}

struct RpcResponse {
    payload: Vec<u8>,
    is_backend_error: bool,
}

struct CompanionAdvertiser {
    daemon: ServiceDaemon,
}

impl Drop for CompanionAdvertiser {
    fn drop(&mut self) {
        if let Err(error) = self.daemon.shutdown() {
            warn!("failed to stop companion Bonjour advertisement: {error}");
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt::init();

    let settings = Settings::load().map_err(|e| anyhow::anyhow!("{e}"))?;
    let pool = create_pool(&settings.database())
        .await
        .map_err(|e| anyhow::anyhow!("failed to connect to Postgres: {e}"))?;
    run_migrations(&pool)
        .await
        .map_err(|e| anyhow::anyhow!("failed to run migrations: {e}"))?;

    let api = settings.api();
    let deployment_kind = match api.deployment_kind {
        ApiDeploymentKind::Companion => DeploymentKind::Companion,
        ApiDeploymentKind::Cloud => DeploymentKind::Cloud,
    };
    let instance_id = api
        .instance_id
        .clone()
        .unwrap_or_else(|| Uuid::new_v4().to_string());
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

    let state = Arc::new(ServerState {
        surface: Some(Arc::new(services)),
        sessions: Arc::new(SessionManager::new(
            pool,
            CapabilitiesResponse {
                supports_remote_anki: true,
                supports_atlas: true,
                deployment_kind,
                execution_mode: ExecutionMode::Remote,
            },
            instance_id.clone(),
        )),
        deployment_kind,
        pairing_api_key: api.api_key.clone(),
        pairing_account: AccountResponse {
            account_id: api.account_id.clone(),
            account_display_name: api.account_display_name.clone(),
        },
    });
    start_cleanup_task(state.sessions.clone());
    let _companion_advertiser = maybe_start_companion_advertiser(
        deployment_kind,
        addr,
        &state.pairing_account,
        &instance_id,
    );

    let app = build_app(state);

    info!("atlas server listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

fn maybe_start_companion_advertiser(
    deployment_kind: DeploymentKind,
    addr: SocketAddr,
    account: &AccountResponse,
    instance_id: &str,
) -> Option<CompanionAdvertiser> {
    if deployment_kind != DeploymentKind::Companion {
        return None;
    }

    let advertised_ips = match discover_companion_addresses(addr) {
        Ok(addresses) if !addresses.is_empty() => addresses,
        Ok(_) => {
            warn!("no companion addresses available for Bonjour advertisement");
            return None;
        }
        Err(error) => {
            warn!("failed to enumerate companion addresses for Bonjour advertisement: {error}");
            return None;
        }
    };

    let daemon = match ServiceDaemon::new() {
        Ok(daemon) => daemon,
        Err(error) => {
            warn!("failed to start Bonjour daemon for companion discovery: {error}");
            return None;
        }
    };

    let host_name = format!(
        "anki-atlas-{}.local.",
        instance_id.chars().take(8).collect::<String>()
    );
    let instance_name = format!("Anki Atlas on {}", account.account_display_name);
    let ip_list = advertised_ips
        .iter()
        .map(std::string::ToString::to_string)
        .collect::<Vec<_>>()
        .join(",");
    let properties = HashMap::from([
        ("deployment".to_string(), "companion".to_string()),
        ("supports_remote_anki".to_string(), "true".to_string()),
        ("supports_atlas".to_string(), "true".to_string()),
        ("account_id".to_string(), account.account_id.clone()),
        (
            "account_display_name".to_string(),
            account.account_display_name.clone(),
        ),
        ("path".to_string(), "/".to_string()),
        ("health".to_string(), "/health".to_string()),
    ]);

    let service_info = match ServiceInfo::new(
        COMPANION_SERVICE_TYPE,
        &instance_name,
        &host_name,
        ip_list.as_str(),
        addr.port(),
        properties,
    ) {
        Ok(service_info) => service_info.enable_addr_auto(),
        Err(error) => {
            warn!("failed to construct Bonjour service info for companion discovery: {error}");
            return None;
        }
    };

    if let Err(error) = daemon.register(service_info) {
        warn!("failed to register Bonjour service for companion discovery: {error}");
        return None;
    }

    info!(
        "advertising companion discovery service {COMPANION_SERVICE_KIND} on port {}",
        addr.port()
    );
    Some(CompanionAdvertiser { daemon })
}

fn discover_companion_addresses(addr: SocketAddr) -> anyhow::Result<Vec<String>> {
    let mut addresses: Vec<String> = Vec::new();

    if let std::net::IpAddr::V4(ipv4) = addr.ip()
        && !ipv4.is_unspecified()
        && !ipv4.is_loopback()
    {
        addresses.push(ipv4.to_string());
    }

    for interface in get_if_addrs()? {
        if let IfAddr::V4(ipv4) = interface.addr {
            if ipv4.ip.is_loopback() {
                continue;
            }

            let rendered = ipv4.ip.to_string();
            if !addresses.contains(&rendered) {
                addresses.push(rendered);
            }
        }
    }

    if addresses.is_empty()
        && let std::net::IpAddr::V4(ipv4) = addr.ip()
        && !ipv4.is_unspecified()
    {
        addresses.push(ipv4.to_string());
    }

    Ok(addresses)
}

fn build_app(state: SharedState) -> Router {
    Router::new()
        .route("/api/auth/pair/create", post(handle_pair_create))
        .route("/api/auth/pair/exchange", post(handle_pair_exchange))
        .route("/api/auth/refresh", post(handle_refresh))
        .route("/api/auth/logout", post(handle_logout))
        .route("/api/me", get(handle_me))
        .route("/api/capabilities", get(handle_capabilities))
        .route("/api/anki/backend/init", post(handle_backend_init))
        .route("/api/anki/backend/free", post(handle_backend_free))
        .route("/api/anki/rpc/{service}/{method}", post(handle_backend_rpc))
        .route("/api/search", post(handle_search))
        .route("/api/search_chunks", post(handle_search_chunks))
        .route("/api/get_taxonomy_tree", post(handle_taxonomy_tree))
        .route("/api/get_coverage", post(handle_coverage))
        .route("/api/get_gaps", post(handle_gaps))
        .route("/api/get_weak_notes", post(handle_weak_notes))
        .route("/api/find_duplicates", post(handle_duplicates))
        .route("/api/kg_status", post(handle_kg_status))
        .route("/api/kg_refresh", post(handle_kg_refresh))
        .route("/api/kg_note_links", post(handle_kg_note_links))
        .route(
            "/api/kg_topic_neighborhood",
            post(handle_kg_topic_neighborhood),
        )
        .route("/api/generate_preview", post(handle_generate_preview))
        .route("/api/obsidian_scan", post(handle_obsidian_scan))
        .route("/health", get(handle_health))
        .layer(CorsLayer::permissive())
        .with_state(state)
}

fn start_cleanup_task(session_manager: Arc<SessionManager>) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(300));
        loop {
            interval.tick().await;
            if let Err(error) = session_manager.purge_expired().await {
                warn!("failed to purge expired remote sessions: {error:?}");
            }
        }
    });
}

async fn handle_health() -> &'static str {
    "ok"
}

#[derive(Debug)]
struct AppError(StatusCode, String);

impl AppError {
    fn internal(e: impl std::fmt::Display) -> Self {
        Self(StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    }

    fn bad_request(e: impl std::fmt::Display) -> Self {
        Self(StatusCode::BAD_REQUEST, e.to_string())
    }

    fn unauthorized(e: impl std::fmt::Display) -> Self {
        Self(StatusCode::UNAUTHORIZED, e.to_string())
    }

    fn not_found(e: impl std::fmt::Display) -> Self {
        Self(StatusCode::NOT_FOUND, e.to_string())
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let body = serde_json::json!({ "error": self.1 });
        (self.0, axum::Json(body)).into_response()
    }
}

fn surface_services(state: &ServerState) -> Result<&SurfaceServices, AppError> {
    state
        .surface
        .as_deref()
        .ok_or_else(|| AppError::internal("Surface services are unavailable."))
}

fn bearer_token(headers: &HeaderMap) -> Result<&str, AppError> {
    let header = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| AppError::unauthorized("Missing authorization header."))?;
    header.strip_prefix("Bearer ").ok_or_else(|| {
        AppError::unauthorized("Authorization header must use Bearer authentication.")
    })
}

fn backend_session_id(headers: &HeaderMap) -> Result<&str, AppError> {
    headers
        .get(BACKEND_SESSION_HEADER)
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| AppError::unauthorized("Missing backend session header."))
}

async fn require_auth(
    state: &ServerState,
    headers: &HeaderMap,
) -> Result<AuthSessionRecord, AppError> {
    let token = bearer_token(headers)?;
    state.sessions.session_for_access_token(token).await
}

fn require_pairing_create_auth(state: &ServerState, headers: &HeaderMap) -> Result<(), AppError> {
    if state.deployment_kind != DeploymentKind::Cloud {
        return Ok(());
    }

    let expected_api_key = state.pairing_api_key.as_deref().ok_or_else(|| {
        AppError::internal("Cloud deployment is missing the required pairing API key.")
    })?;
    let provided_token = bearer_token(headers)?;
    if provided_token != expected_api_key {
        return Err(AppError::unauthorized(
            "Cloud pairing requires a valid pairing API key.",
        ));
    }

    Ok(())
}

async fn handle_pair_create(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<PairingCreateInput>,
) -> Result<axum::Json<PairingCodeResponse>, AppError> {
    require_pairing_create_auth(&state, &headers)?;
    let response = state
        .sessions
        .create_pairing_code(
            input.device_name,
            &state.pairing_account.account_id,
            &state.pairing_account.account_display_name,
        )
        .await?;
    Ok(axum::Json(response))
}

async fn handle_pair_exchange(
    State(state): State<SharedState>,
    axum::Json(input): axum::Json<PairingExchangeInput>,
) -> Result<axum::Json<AuthSessionResponse>, AppError> {
    let response = state
        .sessions
        .exchange_pairing_code(&input.pairing_code)
        .await?;
    Ok(axum::Json(response))
}

async fn handle_refresh(
    State(state): State<SharedState>,
    axum::Json(input): axum::Json<RefreshInput>,
) -> Result<axum::Json<AuthSessionResponse>, AppError> {
    let response = state.sessions.refresh_session(&input.refresh_token).await?;
    Ok(axum::Json(response))
}

async fn handle_logout(
    State(state): State<SharedState>,
    headers: HeaderMap,
    body: Option<axum::Json<LogoutInput>>,
) -> Result<StatusCode, AppError> {
    let access_token = bearer_token(&headers)?;
    state
        .sessions
        .logout(
            access_token,
            body.as_ref()
                .and_then(|value| value.refresh_token.as_deref()),
        )
        .await;
    Ok(StatusCode::NO_CONTENT)
}

async fn handle_me(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Result<axum::Json<MeResponse>, AppError> {
    let session = require_auth(&state, &headers).await?;
    Ok(axum::Json(MeResponse {
        account: AccountResponse {
            account_id: session.account_id,
            account_display_name: session.account_display_name,
        },
        capabilities: session.capabilities,
    }))
}

async fn handle_capabilities(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Result<axum::Json<CapabilitiesResponse>, AppError> {
    let session = require_auth(&state, &headers).await?;
    Ok(axum::Json(session.capabilities))
}

async fn handle_backend_init(
    State(state): State<SharedState>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<axum::Json<BackendSessionInitResponse>, AppError> {
    let access_token = bearer_token(&headers)?;
    let response = state
        .sessions
        .create_backend_session(access_token, body.as_ref())
        .await?;
    Ok(axum::Json(response))
}

async fn handle_backend_free(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Result<StatusCode, AppError> {
    let access_token = bearer_token(&headers)?;
    let session_id = backend_session_id(&headers)?;
    state
        .sessions
        .free_backend_session(access_token, session_id)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn handle_backend_rpc(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path((service, method)): Path<(u32, u32)>,
    body: Bytes,
) -> Result<Response, AppError> {
    let access_token = bearer_token(&headers)?;
    let session_id = backend_session_id(&headers)?;
    let response = state
        .sessions
        .run_backend_rpc(access_token, session_id, service, method, body.as_ref())
        .await?;

    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/x-protobuf"),
    );
    headers.insert(
        BACKEND_ERROR_HEADER,
        HeaderValue::from_static(if response.is_backend_error { "1" } else { "0" }),
    );

    Ok((StatusCode::OK, headers, Body::from(response.payload)).into_response())
}

async fn handle_search(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(request): axum::Json<surface_contracts::search::SearchRequest>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .search
        .search(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

async fn handle_search_chunks(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(request): axum::Json<surface_contracts::search::ChunkSearchRequest>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .search
        .search_chunks(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize, Default)]
struct TaxonomyTreeInput {
    root_path: Option<String>,
}

async fn handle_taxonomy_tree(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<TaxonomyTreeInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .analytics
        .get_taxonomy_tree(input.root_path)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct CoverageInput {
    topic_path: String,
    #[serde(default)]
    include_subtree: bool,
}

async fn handle_coverage(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<CoverageInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .analytics
        .get_coverage(input.topic_path, input.include_subtree)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct GapsInput {
    topic_path: String,
    #[serde(default)]
    min_coverage: i64,
}

async fn handle_gaps(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<GapsInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .analytics
        .get_gaps(input.topic_path, input.min_coverage)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
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
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<WeakNotesInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .analytics
        .get_weak_notes(input.topic_path, input.max_results)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
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
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<DuplicatesInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
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
        .map(axum::Json)
        .map_err(AppError::internal)
}

async fn handle_kg_status(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .knowledge_graph
        .status()
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

async fn handle_kg_refresh(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(request): axum::Json<RefreshKnowledgeGraphRequest>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .knowledge_graph
        .refresh(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

async fn handle_kg_note_links(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(request): axum::Json<NoteLinksRequest>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .knowledge_graph
        .note_links(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

async fn handle_kg_topic_neighborhood(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(request): axum::Json<TopicNeighborhoodRequest>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let result = services
        .knowledge_graph
        .topic_neighborhood(&request)
        .await
        .map_err(AppError::internal)?;
    serde_json::to_value(result)
        .map(axum::Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct GeneratePreviewInput {
    file_path: String,
}

async fn handle_generate_preview(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<GeneratePreviewInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let preview = services
        .generate_preview
        .preview(PathBuf::from(&input.file_path).as_path())
        .map_err(AppError::bad_request)?;
    serde_json::to_value(preview)
        .map(axum::Json)
        .map_err(AppError::internal)
}

#[derive(Deserialize)]
struct ObsidianScanInput {
    vault_path: String,
    #[serde(default)]
    source_dirs: Vec<String>,
}

async fn handle_obsidian_scan(
    State(state): State<SharedState>,
    headers: HeaderMap,
    axum::Json(input): axum::Json<ObsidianScanInput>,
) -> Result<axum::Json<Value>, AppError> {
    require_auth(&state, &headers).await?;
    let services = surface_services(&state)?;
    let preview = services
        .obsidian_scan
        .scan(
            PathBuf::from(&input.vault_path).as_path(),
            &input.source_dirs,
            common::ExecutionMode::DryRun,
        )
        .map_err(AppError::bad_request)?;
    serde_json::to_value(preview)
        .map(axum::Json)
        .map_err(AppError::internal)
}

#[cfg(test)]
mod tests {
    use super::*;
    use anki::backend::init_backend;
    use anki_proto::generic::Empty;
    use axum::body::to_bytes;
    use axum::http::Request;
    use prost::Message;
    use sqlx::PgPool;
    use sqlx::postgres::PgPoolOptions;
    use testcontainers::ImageExt;
    use testcontainers::runners::AsyncRunner;
    use testcontainers_modules::postgres::Postgres;
    use tower::util::ServiceExt;

    async fn setup_pool() -> Option<(PgPool, testcontainers::ContainerAsync<Postgres>)> {
        let container = match Postgres::default()
            .with_name("pgvector/pgvector")
            .with_tag("pg16")
            .start()
            .await
        {
            Ok(container) => container,
            Err(error) => {
                eprintln!("skipping postgres-backed server test: {error}");
                return None;
            }
        };
        let host = container.get_host().await.expect("postgres host");
        let port = container
            .get_host_port_ipv4(5432)
            .await
            .expect("postgres port");
        let url = format!("postgresql://postgres:postgres@{host}:{port}/postgres");
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(&url)
            .await
            .expect("postgres pool");
        run_migrations(&pool).await.expect("server migrations");
        Some((pool, container))
    }

    fn test_state(
        pool: PgPool,
        deployment_kind: DeploymentKind,
        instance_id: &str,
        pairing_api_key: Option<&str>,
    ) -> SharedState {
        let (account_id, account_display_name) = match deployment_kind {
            DeploymentKind::Companion => ("local-companion", "Anki Companion"),
            DeploymentKind::Cloud => ("cloud-account", "Anki Cloud"),
        };
        Arc::new(ServerState {
            surface: None,
            sessions: Arc::new(SessionManager::new(
                pool,
                CapabilitiesResponse {
                    supports_remote_anki: true,
                    supports_atlas: false,
                    deployment_kind,
                    execution_mode: ExecutionMode::Remote,
                },
                instance_id.to_string(),
            )),
            deployment_kind,
            pairing_api_key: pairing_api_key.map(ToOwned::to_owned),
            pairing_account: AccountResponse {
                account_id: account_id.to_string(),
                account_display_name: account_display_name.to_string(),
            },
        })
    }

    async fn pairing_code(app: Router, pairing_api_key: Option<&str>) -> Response {
        let mut builder = Request::builder()
            .method("POST")
            .uri("/api/auth/pair/create")
            .header(header::CONTENT_TYPE, "application/json");
        if let Some(pairing_api_key) = pairing_api_key {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {pairing_api_key}"));
        }
        app.oneshot(
            builder
                .body(Body::from(r#"{"device_name":"Test Device"}"#))
                .expect("pair request"),
        )
        .await
        .expect("pair response")
    }

    async fn successful_pairing_code(
        app: Router,
        pairing_api_key: Option<&str>,
    ) -> PairingCodeResponse {
        let pair_response = pairing_code(app, pairing_api_key).await;
        assert_eq!(pair_response.status(), StatusCode::OK);
        let pair_body = to_bytes(pair_response.into_body(), usize::MAX)
            .await
            .expect("pair body");
        serde_json::from_slice(&pair_body).expect("pairing json")
    }

    async fn auth_session(app: Router) -> AuthSessionResponse {
        let pairing = successful_pairing_code(app.clone(), None).await;
        let exchange_payload = serde_json::to_vec(&serde_json::json!({
            "pairing_code": pairing.pairing_code
        }))
        .expect("pairing exchange json");
        let exchange_response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/pair/exchange")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(exchange_payload))
                    .expect("exchange request"),
            )
            .await
            .expect("exchange response");
        assert_eq!(exchange_response.status(), StatusCode::OK);
        let exchange_body = to_bytes(exchange_response.into_body(), usize::MAX)
            .await
            .expect("exchange body");
        serde_json::from_slice(&exchange_body).expect("auth session json")
    }

    #[tokio::test]
    async fn pairing_survives_process_restart_and_me_works() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app1 = build_app(test_state(
            pool.clone(),
            DeploymentKind::Companion,
            "instance-a",
            None,
        ));
        let pairing = successful_pairing_code(app1, None).await;
        let app2 = build_app(test_state(
            pool,
            DeploymentKind::Companion,
            "instance-b",
            None,
        ));

        let exchange_payload = serde_json::to_vec(&serde_json::json!({
            "pairing_code": pairing.pairing_code
        }))
        .expect("pairing exchange json");
        let exchange_response = app2
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/pair/exchange")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(exchange_payload))
                    .expect("exchange request"),
            )
            .await
            .expect("exchange response");
        assert_eq!(exchange_response.status(), StatusCode::OK);
        let exchange_body = to_bytes(exchange_response.into_body(), usize::MAX)
            .await
            .expect("exchange body");
        let auth: AuthSessionResponse =
            serde_json::from_slice(&exchange_body).expect("auth session json");

        let response = app2
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/api/me")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .body(Body::empty())
                    .expect("me request"),
            )
            .await
            .expect("me response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("me body");
        let me: MeResponse = serde_json::from_slice(&body).expect("me json");
        assert_eq!(me.account.account_id, "local-companion");
        assert!(me.capabilities.supports_remote_anki);
    }

    #[tokio::test]
    async fn auth_refresh_survives_process_restart() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app1 = build_app(test_state(
            pool.clone(),
            DeploymentKind::Companion,
            "instance-a",
            None,
        ));
        let auth = auth_session(app1).await;
        let app2 = build_app(test_state(
            pool,
            DeploymentKind::Companion,
            "instance-b",
            None,
        ));

        let refresh_payload = serde_json::to_vec(&serde_json::json!({
            "refresh_token": auth.refresh_token
        }))
        .expect("refresh json");
        let response = app2
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/refresh")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(refresh_payload))
                    .expect("refresh request"),
            )
            .await
            .expect("refresh response");
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn logout_revokes_sessions_durably() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app1 = build_app(test_state(
            pool.clone(),
            DeploymentKind::Companion,
            "instance-a",
            None,
        ));
        let auth = auth_session(app1).await;
        let app2 = build_app(test_state(
            pool.clone(),
            DeploymentKind::Companion,
            "instance-b",
            None,
        ));

        let logout_payload = serde_json::to_vec(&serde_json::json!({
            "refresh_token": auth.refresh_token
        }))
        .expect("logout json");
        let logout = app2
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/logout")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(logout_payload))
                    .expect("logout request"),
            )
            .await
            .expect("logout response");
        assert_eq!(logout.status(), StatusCode::NO_CONTENT);

        let app3 = build_app(test_state(
            pool,
            DeploymentKind::Companion,
            "instance-c",
            None,
        ));
        let me = app3
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/api/me")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .body(Body::empty())
                    .expect("me request"),
            )
            .await
            .expect("me response");
        assert_eq!(me.status(), StatusCode::UNAUTHORIZED);

        let refresh_payload = serde_json::to_vec(&serde_json::json!({
            "refresh_token": auth.refresh_token
        }))
        .expect("refresh json");
        let refresh = app3
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/refresh")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(refresh_payload))
                    .expect("refresh request"),
            )
            .await
            .expect("refresh response");
        assert_eq!(refresh.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn backend_lease_rows_are_created_and_closed() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app = build_app(test_state(
            pool.clone(),
            DeploymentKind::Companion,
            "instance-a",
            None,
        ));
        let auth = auth_session(app.clone()).await;

        let init_msg = anki_proto::backend::BackendInit {
            preferred_langs: vec!["en".to_string()],
            locale_folder_path: String::new(),
            server: true,
        };
        let init_bytes = init_msg.encode_to_vec();

        let init_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/anki/backend/init")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .header(header::CONTENT_TYPE, "application/x-protobuf")
                    .body(Body::from(init_bytes.clone()))
                    .expect("backend init request"),
            )
            .await
            .expect("backend init response");
        assert_eq!(init_response.status(), StatusCode::OK);
        let init_body = to_bytes(init_response.into_body(), usize::MAX)
            .await
            .expect("backend init body");
        let backend_session: BackendSessionInitResponse =
            serde_json::from_slice(&init_body).expect("backend init json");
        let backend_session_id = backend_session.backend_session_id.clone();

        let closed_at: Option<Option<chrono::DateTime<chrono::Utc>>> = sqlx::query_scalar(
            "SELECT closed_at FROM remote_backend_leases WHERE backend_session_id = $1",
        )
        .bind(&backend_session_id)
        .fetch_optional(&pool)
        .await
        .expect("lease row query");
        assert_eq!(closed_at.flatten(), None);

        let local_backend = init_backend(&init_bytes).expect("local backend");
        let input = Empty {}.encode_to_vec();
        let (local_output, expected_error_header) =
            match local_backend.run_service_method(3, 7, &input) {
                Ok(payload) => (payload, "0"),
                Err(payload) => (payload, "1"),
            };

        let rpc_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/anki/rpc/3/7")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .header(BACKEND_SESSION_HEADER, &backend_session_id)
                    .header(header::CONTENT_TYPE, "application/x-protobuf")
                    .body(Body::from(input))
                    .expect("rpc request"),
            )
            .await
            .expect("rpc response");

        assert_eq!(rpc_response.status(), StatusCode::OK);
        assert_eq!(
            rpc_response
                .headers()
                .get(BACKEND_ERROR_HEADER)
                .and_then(|value| value.to_str().ok()),
            Some(expected_error_header)
        );
        let rpc_body = to_bytes(rpc_response.into_body(), usize::MAX)
            .await
            .expect("rpc body");
        assert_eq!(rpc_body.as_ref(), local_output.as_slice());

        let free_response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/anki/backend/free")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .header(BACKEND_SESSION_HEADER, &backend_session_id)
                    .body(Body::empty())
                    .expect("backend free request"),
            )
            .await
            .expect("backend free response");
        assert_eq!(free_response.status(), StatusCode::NO_CONTENT);

        let closed_after_free: Option<Option<chrono::DateTime<chrono::Utc>>> = sqlx::query_scalar(
            "SELECT closed_at FROM remote_backend_leases WHERE backend_session_id = $1",
        )
        .bind(&backend_session_id)
        .fetch_optional(&pool)
        .await
        .expect("lease row query");
        assert!(closed_after_free.flatten().is_some());
    }

    #[tokio::test]
    async fn rpc_returns_not_found_when_runtime_cache_is_lost_after_restart() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app1 = build_app(test_state(
            pool.clone(),
            DeploymentKind::Companion,
            "instance-a",
            None,
        ));
        let auth = auth_session(app1.clone()).await;

        let init_msg = anki_proto::backend::BackendInit {
            preferred_langs: vec!["en".to_string()],
            locale_folder_path: String::new(),
            server: true,
        };
        let init_bytes = init_msg.encode_to_vec();
        let init_response = app1
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/anki/backend/init")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .header(header::CONTENT_TYPE, "application/x-protobuf")
                    .body(Body::from(init_bytes))
                    .expect("backend init request"),
            )
            .await
            .expect("backend init response");
        let init_body = to_bytes(init_response.into_body(), usize::MAX)
            .await
            .expect("backend init body");
        let backend_session: BackendSessionInitResponse =
            serde_json::from_slice(&init_body).expect("backend init json");

        let app2 = build_app(test_state(
            pool,
            DeploymentKind::Companion,
            "instance-b",
            None,
        ));
        let rpc_response = app2
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/anki/rpc/3/7")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .header(BACKEND_SESSION_HEADER, backend_session.backend_session_id)
                    .header(header::CONTENT_TYPE, "application/x-protobuf")
                    .body(Body::from(Empty {}.encode_to_vec()))
                    .expect("rpc request"),
            )
            .await
            .expect("rpc response");
        assert_eq!(rpc_response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn capabilities_reflect_cloud_deployment_config() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app = build_app(test_state(
            pool,
            DeploymentKind::Cloud,
            "instance-cloud",
            Some("cloud-admin-key"),
        ));
        let pairing = successful_pairing_code(app.clone(), Some("cloud-admin-key")).await;
        let exchange_payload = serde_json::to_vec(&serde_json::json!({
            "pairing_code": pairing.pairing_code
        }))
        .expect("pairing exchange json");
        let exchange = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/pair/exchange")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(exchange_payload))
                    .expect("exchange request"),
            )
            .await
            .expect("exchange response");
        assert_eq!(exchange.status(), StatusCode::OK);
        let exchange_body = to_bytes(exchange.into_body(), usize::MAX)
            .await
            .expect("exchange body");
        let auth: AuthSessionResponse =
            serde_json::from_slice(&exchange_body).expect("auth session json");

        let response = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/api/capabilities")
                    .header(
                        header::AUTHORIZATION,
                        format!("Bearer {}", auth.access_token),
                    )
                    .body(Body::empty())
                    .expect("capabilities request"),
            )
            .await
            .expect("capabilities response");
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("capabilities body");
        let capabilities: CapabilitiesResponse =
            serde_json::from_slice(&body).expect("capabilities json");
        assert!(matches!(
            capabilities.deployment_kind,
            DeploymentKind::Cloud
        ));
    }

    #[tokio::test]
    async fn cloud_pairing_requires_api_key_and_uses_cloud_account() {
        let Some((pool, _container)) = setup_pool().await else {
            return;
        };
        let app = build_app(test_state(
            pool,
            DeploymentKind::Cloud,
            "instance-cloud",
            Some("cloud-admin-key"),
        ));

        let unauthorized_pair = pairing_code(app.clone(), None).await;
        assert_eq!(unauthorized_pair.status(), StatusCode::UNAUTHORIZED);

        let pairing = successful_pairing_code(app.clone(), Some("cloud-admin-key")).await;
        let exchange_payload = serde_json::to_vec(&serde_json::json!({
            "pairing_code": pairing.pairing_code
        }))
        .expect("pairing exchange json");
        let exchange_response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/pair/exchange")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(exchange_payload))
                    .expect("exchange request"),
            )
            .await
            .expect("exchange response");
        assert_eq!(exchange_response.status(), StatusCode::OK);

        let exchange_body = to_bytes(exchange_response.into_body(), usize::MAX)
            .await
            .expect("exchange body");
        let auth: AuthSessionResponse =
            serde_json::from_slice(&exchange_body).expect("auth session json");
        assert_eq!(auth.account_id, "cloud-account");
        assert_eq!(auth.account_display_name, "Anki Cloud");
    }
}
