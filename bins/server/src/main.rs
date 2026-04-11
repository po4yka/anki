use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anki::backend::{Backend, init_backend};
use anki_proto::generic::Empty;
use axum::{
    Router,
    body::{Body, Bytes},
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use chrono::{DateTime, Utc};
use common::config::Settings;
use prost::Message;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use surface_contracts::knowledge_graph::{
    NoteLinksRequest, RefreshKnowledgeGraphRequest, TopicNeighborhoodRequest,
};
use surface_runtime::{BuildSurfaceServicesOptions, SurfaceServices, build_surface_services};
use tower::util::ServiceExt;
use tower_http::cors::CorsLayer;
use tracing::info;
use uuid::Uuid;

type SurfaceState = Arc<SurfaceServices>;
type SharedState = Arc<ServerState>;

const ACCESS_TOKEN_TTL: i64 = 60 * 60;
const REFRESH_TOKEN_TTL: i64 = 60 * 60 * 24 * 30;
const PAIRING_CODE_TTL: i64 = 60 * 10;
const BACKEND_SESSION_TTL: i64 = 60 * 30;
const BACKEND_SESSION_HEADER: &str = "x-anki-backend-session";
const BACKEND_ERROR_HEADER: &str = "x-anki-error";

#[derive(Clone)]
struct ServerState {
    surface: Option<SurfaceState>,
    sessions: Arc<SessionManager>,
}

#[derive(Default)]
struct SessionManager {
    inner: Mutex<SessionState>,
}

#[derive(Default)]
struct SessionState {
    pairings: HashMap<String, PairingRecord>,
    access_sessions: HashMap<String, AuthSessionRecord>,
    refresh_index: HashMap<String, String>,
    backend_sessions: HashMap<String, BackendSessionRecord>,
}

#[derive(Clone)]
struct PairingRecord {
    expires_at: DateTime<Utc>,
    account_id: String,
    account_display_name: String,
}

#[derive(Clone)]
struct AuthSessionRecord {
    access_token: String,
    refresh_token: String,
    account_id: String,
    account_display_name: String,
    access_expires_at: DateTime<Utc>,
    refresh_expires_at: DateTime<Utc>,
    capabilities: CapabilitiesResponse,
}

#[derive(Clone)]
struct BackendSessionRecord {
    owner_account_id: String,
    backend: Backend,
    expires_at: DateTime<Utc>,
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

#[derive(Clone, Copy, Serialize, Deserialize)]
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

    let state = Arc::new(ServerState {
        surface: Some(Arc::new(services)),
        sessions: Arc::new(SessionManager::default()),
    });

    let app = build_app(state);

    info!("atlas server listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
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

impl SessionManager {
    fn capabilities(&self, supports_atlas: bool) -> CapabilitiesResponse {
        CapabilitiesResponse {
            supports_remote_anki: true,
            supports_atlas,
            deployment_kind: DeploymentKind::Companion,
            execution_mode: ExecutionMode::Remote,
        }
    }

    fn create_pairing_code(
        &self,
        supports_atlas: bool,
        device_name: Option<String>,
    ) -> PairingCodeResponse {
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        purge_expired(&mut state);

        let code = Uuid::new_v4()
            .simple()
            .to_string()
            .chars()
            .take(8)
            .collect::<String>()
            .to_uppercase();
        let expires_at = Utc::now() + chrono::TimeDelta::seconds(PAIRING_CODE_TTL);
        let account_display_name = device_name
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| "Anki Companion".to_string());

        state.pairings.insert(
            code.clone(),
            PairingRecord {
                expires_at,
                account_id: "local-companion".to_string(),
                account_display_name: account_display_name.clone(),
            },
        );

        let _ = self.capabilities(supports_atlas);
        PairingCodeResponse {
            pairing_code: code.clone(),
            pairing_url: format!("ankiapp://pair?code={code}"),
            expires_at: expires_at.to_rfc3339(),
        }
    }

    fn exchange_pairing_code(
        &self,
        pairing_code: &str,
        supports_atlas: bool,
    ) -> Result<AuthSessionResponse, AppError> {
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        purge_expired(&mut state);

        let pairing = state
            .pairings
            .remove(pairing_code)
            .ok_or_else(|| AppError::unauthorized("Invalid or expired pairing code."))?;

        let access_token = Uuid::new_v4().to_string();
        let refresh_token = Uuid::new_v4().to_string();
        let access_expires_at = Utc::now() + chrono::TimeDelta::seconds(ACCESS_TOKEN_TTL);
        let refresh_expires_at = Utc::now() + chrono::TimeDelta::seconds(REFRESH_TOKEN_TTL);
        let capabilities = self.capabilities(supports_atlas);

        let record = AuthSessionRecord {
            access_token: access_token.clone(),
            refresh_token: refresh_token.clone(),
            account_id: pairing.account_id,
            account_display_name: pairing.account_display_name,
            access_expires_at,
            refresh_expires_at,
            capabilities: capabilities.clone(),
        };
        state
            .refresh_index
            .insert(refresh_token.clone(), access_token.clone());
        state
            .access_sessions
            .insert(access_token.clone(), record.clone());

        Ok(auth_session_response(&record))
    }

    fn refresh_session(
        &self,
        refresh_token: &str,
        supports_atlas: bool,
    ) -> Result<AuthSessionResponse, AppError> {
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        purge_expired(&mut state);

        let existing_access = state
            .refresh_index
            .get(refresh_token)
            .cloned()
            .ok_or_else(|| AppError::unauthorized("Refresh token is invalid or expired."))?;
        let existing = state
            .access_sessions
            .remove(&existing_access)
            .ok_or_else(|| AppError::unauthorized("Session is no longer available."))?;

        if existing.refresh_expires_at <= Utc::now() {
            state.refresh_index.remove(refresh_token);
            return Err(AppError::unauthorized(
                "Refresh token is invalid or expired.",
            ));
        }

        let access_token = Uuid::new_v4().to_string();
        let next_refresh_token = Uuid::new_v4().to_string();
        let access_expires_at = Utc::now() + chrono::TimeDelta::seconds(ACCESS_TOKEN_TTL);
        let refresh_expires_at = Utc::now() + chrono::TimeDelta::seconds(REFRESH_TOKEN_TTL);
        let capabilities = self.capabilities(supports_atlas);

        let record = AuthSessionRecord {
            access_token: access_token.clone(),
            refresh_token: next_refresh_token.clone(),
            account_id: existing.account_id,
            account_display_name: existing.account_display_name,
            access_expires_at,
            refresh_expires_at,
            capabilities: capabilities.clone(),
        };

        state.refresh_index.remove(refresh_token);
        state
            .refresh_index
            .insert(next_refresh_token.clone(), access_token.clone());
        state.access_sessions.insert(access_token, record.clone());

        Ok(auth_session_response(&record))
    }

    fn session_for_access_token(&self, access_token: &str) -> Result<AuthSessionRecord, AppError> {
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        purge_expired(&mut state);
        let session = state
            .access_sessions
            .get(access_token)
            .cloned()
            .ok_or_else(|| AppError::unauthorized("Access token is invalid or expired."))?;
        if session.access_expires_at <= Utc::now() {
            state.access_sessions.remove(access_token);
            state.refresh_index.retain(|_, value| value != access_token);
            return Err(AppError::unauthorized(
                "Access token is invalid or expired.",
            ));
        }
        Ok(session)
    }

    fn logout(&self, access_token: &str, refresh_token: Option<&str>) {
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        if let Some(record) = state.access_sessions.remove(access_token) {
            state.refresh_index.remove(&record.refresh_token);
            state
                .backend_sessions
                .retain(|_, session| session.owner_account_id != record.account_id);
        }
        if let Some(refresh_token) = refresh_token {
            state.refresh_index.remove(refresh_token);
        }
    }

    fn create_backend_session(
        &self,
        access_token: &str,
        init_bytes: &[u8],
    ) -> Result<BackendSessionInitResponse, AppError> {
        let session = self.session_for_access_token(access_token)?;
        let backend = init_backend(init_bytes)
            .map_err(|err| AppError::bad_request(format!("Invalid backend init: {err}")))?;
        let session_id = Uuid::new_v4().to_string();

        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        purge_expired(&mut state);
        state.backend_sessions.insert(
            session_id.clone(),
            BackendSessionRecord {
                owner_account_id: session.account_id,
                backend,
                expires_at: Utc::now() + chrono::TimeDelta::seconds(BACKEND_SESSION_TTL),
            },
        );

        Ok(BackendSessionInitResponse {
            backend_session_id: session_id,
        })
    }

    fn free_backend_session(
        &self,
        access_token: &str,
        backend_session_id: &str,
    ) -> Result<(), AppError> {
        let auth_session = self.session_for_access_token(access_token)?;
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        let session = state
            .backend_sessions
            .get(backend_session_id)
            .cloned()
            .ok_or_else(|| AppError::not_found("Backend session was not found."))?;
        if session.owner_account_id != auth_session.account_id {
            return Err(AppError::unauthorized(
                "Backend session does not belong to this account.",
            ));
        }
        state.backend_sessions.remove(backend_session_id);
        Ok(())
    }

    fn run_backend_rpc(
        &self,
        access_token: &str,
        backend_session_id: &str,
        service: u32,
        method: u32,
        input: &[u8],
    ) -> Result<RpcResponse, AppError> {
        let auth_session = self.session_for_access_token(access_token)?;
        let mut state = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        purge_expired(&mut state);
        let session = state
            .backend_sessions
            .get_mut(backend_session_id)
            .ok_or_else(|| AppError::not_found("Backend session was not found."))?;

        if session.owner_account_id != auth_session.account_id {
            return Err(AppError::unauthorized(
                "Backend session does not belong to this account.",
            ));
        }

        session.expires_at = Utc::now() + chrono::TimeDelta::seconds(BACKEND_SESSION_TTL);
        match session.backend.run_service_method(service, method, input) {
            Ok(payload) => Ok(RpcResponse {
                payload,
                is_backend_error: false,
            }),
            Err(payload) => Ok(RpcResponse {
                payload,
                is_backend_error: true,
            }),
        }
    }
}

fn purge_expired(state: &mut SessionState) {
    let now = Utc::now();
    state.pairings.retain(|_, record| record.expires_at > now);

    let expired_access = state
        .access_sessions
        .iter()
        .filter_map(|(token, record)| (record.access_expires_at <= now).then_some(token.clone()))
        .collect::<Vec<_>>();
    for token in expired_access {
        if let Some(record) = state.access_sessions.remove(&token) {
            state.refresh_index.remove(&record.refresh_token);
            state
                .backend_sessions
                .retain(|_, session| session.owner_account_id != record.account_id);
        }
    }

    let expired_refresh = state
        .access_sessions
        .iter()
        .filter_map(|(token, record)| {
            (record.refresh_expires_at <= now).then_some((
                token.clone(),
                record.refresh_token.clone(),
                record.account_id.clone(),
            ))
        })
        .collect::<Vec<_>>();
    for (token, refresh, account_id) in expired_refresh {
        state.access_sessions.remove(&token);
        state.refresh_index.remove(&refresh);
        state
            .backend_sessions
            .retain(|_, session| session.owner_account_id != account_id);
    }

    state
        .backend_sessions
        .retain(|_, record| record.expires_at > now);
}

fn auth_session_response(record: &AuthSessionRecord) -> AuthSessionResponse {
    AuthSessionResponse {
        access_token: record.access_token.clone(),
        refresh_token: record.refresh_token.clone(),
        expires_at: record.access_expires_at.to_rfc3339(),
        account_id: record.account_id.clone(),
        account_display_name: record.account_display_name.clone(),
        capabilities: record.capabilities.clone(),
    }
}

async fn handle_health() -> &'static str {
    "ok"
}

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

fn require_auth(state: &ServerState, headers: &HeaderMap) -> Result<AuthSessionRecord, AppError> {
    let token = bearer_token(headers)?;
    state.sessions.session_for_access_token(token)
}

async fn handle_pair_create(
    State(state): State<SharedState>,
    axum::Json(input): axum::Json<PairingCreateInput>,
) -> Result<axum::Json<PairingCodeResponse>, AppError> {
    let response = state
        .sessions
        .create_pairing_code(state.surface.is_some(), input.device_name);
    Ok(axum::Json(response))
}

async fn handle_pair_exchange(
    State(state): State<SharedState>,
    axum::Json(input): axum::Json<PairingExchangeInput>,
) -> Result<axum::Json<AuthSessionResponse>, AppError> {
    let response = state
        .sessions
        .exchange_pairing_code(&input.pairing_code, state.surface.is_some())?;
    Ok(axum::Json(response))
}

async fn handle_refresh(
    State(state): State<SharedState>,
    axum::Json(input): axum::Json<RefreshInput>,
) -> Result<axum::Json<AuthSessionResponse>, AppError> {
    let response = state
        .sessions
        .refresh_session(&input.refresh_token, state.surface.is_some())?;
    Ok(axum::Json(response))
}

async fn handle_logout(
    State(state): State<SharedState>,
    headers: HeaderMap,
    body: Option<axum::Json<LogoutInput>>,
) -> Result<StatusCode, AppError> {
    let access_token = bearer_token(&headers)?;
    state.sessions.logout(
        access_token,
        body.as_ref()
            .and_then(|value| value.refresh_token.as_deref()),
    );
    Ok(StatusCode::NO_CONTENT)
}

async fn handle_me(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Result<axum::Json<MeResponse>, AppError> {
    let session = require_auth(&state, &headers)?;
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
    let session = require_auth(&state, &headers)?;
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
        .create_backend_session(access_token, body.as_ref())?;
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
        .free_backend_session(access_token, session_id)?;
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
    let response =
        state
            .sessions
            .run_backend_rpc(access_token, session_id, service, method, body.as_ref())?;

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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    require_auth(&state, &headers)?;
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
    use axum::body::to_bytes;
    use axum::http::Request;

    fn test_state() -> SharedState {
        Arc::new(ServerState {
            surface: None,
            sessions: Arc::new(SessionManager::default()),
        })
    }

    async fn auth_session(app: Router) -> AuthSessionResponse {
        let pair_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/auth/pair/create")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"device_name":"Test Device"}"#))
                    .expect("pair request"),
            )
            .await
            .expect("pair response");
        assert_eq!(pair_response.status(), StatusCode::OK);
        let pair_body = to_bytes(pair_response.into_body(), usize::MAX)
            .await
            .expect("pair body");
        let pairing: PairingCodeResponse =
            serde_json::from_slice(&pair_body).expect("pairing json");

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
    async fn pair_exchange_and_me_endpoint_work() {
        let app = build_app(test_state());
        let auth = auth_session(app.clone()).await;

        let response = app
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
    async fn backend_rpc_matches_local_backend_output() {
        let app = build_app(test_state());
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

        let local_backend = init_backend(&init_bytes).expect("local backend");
        let input = Empty {}.encode_to_vec();
        let (local_output, expected_error_header) =
            match local_backend.run_service_method(3, 7, &input) {
                Ok(payload) => (payload, "0"),
                Err(payload) => (payload, "1"),
            };

        let rpc_response = app
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
    }
}
