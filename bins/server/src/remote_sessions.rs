use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use anki::backend::{Backend, init_backend};
use anki_proto::collection::{CloseCollectionRequest, OpenCollectionRequest};
use chrono::{DateTime, Utc};
use prost::Message;
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::{FromRow, PgPool, Postgres, Transaction};
use tracing::warn;
use uuid::Uuid;

use crate::{
    AppError, AuthSessionResponse, BackendSessionInitResponse, CapabilitiesResponse,
    PairingCodeResponse, RpcResponse,
};

const ACCESS_TOKEN_TTL: i64 = 60 * 60;
const REFRESH_TOKEN_TTL: i64 = 60 * 60 * 24 * 30;
const PAIRING_CODE_TTL: i64 = 60 * 10;
const BACKEND_SESSION_TTL: i64 = 60 * 30;

#[derive(Clone)]
pub struct AuthSessionRecord {
    pub account_id: String,
    pub account_display_name: String,
    pub refresh_expires_at: DateTime<Utc>,
    pub capabilities: CapabilitiesResponse,
}

#[derive(Clone)]
pub struct SessionManager {
    store: RemoteSessionStore,
    runtime_cache: Arc<BackendRuntimeCache>,
    capabilities: CapabilitiesResponse,
    instance_id: String,
}

impl SessionManager {
    pub fn new(pool: PgPool, capabilities: CapabilitiesResponse, instance_id: String) -> Self {
        Self {
            store: RemoteSessionStore::new(pool),
            runtime_cache: Arc::new(BackendRuntimeCache::default()),
            capabilities,
            instance_id,
        }
    }

    pub async fn create_pairing_code(
        &self,
        device_name: Option<String>,
    ) -> Result<PairingCodeResponse, AppError> {
        let code = Uuid::new_v4()
            .simple()
            .to_string()
            .chars()
            .take(8)
            .collect::<String>()
            .to_uppercase();
        let expires_at = Utc::now() + chrono::TimeDelta::seconds(PAIRING_CODE_TTL);
        let account_display_name = device_name
            .clone()
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| "Anki Companion".to_string());

        self.store
            .insert_pairing(
                &code,
                "local-companion",
                &account_display_name,
                device_name.as_deref(),
                expires_at,
            )
            .await?;

        Ok(PairingCodeResponse {
            pairing_code: code.clone(),
            pairing_url: format!("ankiapp://pair?code={code}"),
            expires_at: expires_at.to_rfc3339(),
        })
    }

    pub async fn exchange_pairing_code(
        &self,
        pairing_code: &str,
    ) -> Result<AuthSessionResponse, AppError> {
        let pairing = self.store.consume_pairing(pairing_code).await?;
        let issued = IssuedAuthSession::new(
            pairing.account_id,
            pairing.account_display_name,
            self.capabilities.clone(),
        );
        self.store.insert_auth_session(&issued).await?;
        Ok(issued.response())
    }

    pub async fn refresh_session(
        &self,
        refresh_token: &str,
    ) -> Result<AuthSessionResponse, AppError> {
        let existing = self.store.auth_session_for_refresh(refresh_token).await?;
        if existing.refresh_expires_at <= Utc::now() {
            return Err(AppError::unauthorized(
                "Refresh token is invalid or expired.",
            ));
        }

        let issued = IssuedAuthSession::new(
            existing.account_id,
            existing.account_display_name,
            self.capabilities.clone(),
        );
        self.store
            .rotate_auth_session(refresh_token, &issued)
            .await?;
        Ok(issued.response())
    }

    pub async fn session_for_access_token(
        &self,
        access_token: &str,
    ) -> Result<AuthSessionRecord, AppError> {
        self.store.auth_session_for_access(access_token).await
    }

    pub async fn logout(&self, access_token: &str, refresh_token: Option<&str>) {
        match self
            .store
            .revoke_auth_session(access_token, refresh_token)
            .await
        {
            Ok(account_ids) => {
                for account_id in account_ids {
                    self.runtime_cache.remove_owned_by(&account_id);
                }
            }
            Err(error) => warn!("failed to revoke remote auth session: {error:?}"),
        }
    }

    pub async fn create_backend_session(
        &self,
        access_token: &str,
        init_bytes: &[u8],
    ) -> Result<BackendSessionInitResponse, AppError> {
        let session = self.session_for_access_token(access_token).await?;
        let backend = init_backend(init_bytes)
            .map_err(|err| AppError::bad_request(format!("Invalid backend init: {err}")))?;
        let session_id = Uuid::new_v4().to_string();
        let expires_at = Utc::now() + chrono::TimeDelta::seconds(BACKEND_SESSION_TTL);

        self.runtime_cache.insert(
            session_id.clone(),
            session.account_id.clone(),
            backend,
            expires_at,
        );

        if let Err(error) = self
            .store
            .create_backend_lease(
                &session_id,
                &session.account_id,
                &self.instance_id,
                init_bytes,
                expires_at,
            )
            .await
        {
            self.runtime_cache.remove(&session_id);
            return Err(error);
        }

        Ok(BackendSessionInitResponse {
            backend_session_id: session_id,
        })
    }

    pub async fn free_backend_session(
        &self,
        access_token: &str,
        backend_session_id: &str,
    ) -> Result<(), AppError> {
        let auth_session = self.session_for_access_token(access_token).await?;
        let lease = self.store.active_backend_lease(backend_session_id).await?;
        if lease.owner_account_id != auth_session.account_id {
            return Err(AppError::unauthorized(
                "Backend session does not belong to this account.",
            ));
        }

        self.store.close_backend_lease(backend_session_id).await?;
        self.runtime_cache.remove(backend_session_id);
        Ok(())
    }

    pub async fn run_backend_rpc(
        &self,
        access_token: &str,
        backend_session_id: &str,
        service: u32,
        method: u32,
        input: &[u8],
    ) -> Result<RpcResponse, AppError> {
        let auth_session = self.session_for_access_token(access_token).await?;
        let lease = self.store.active_backend_lease(backend_session_id).await?;

        if lease.owner_account_id != auth_session.account_id {
            return Err(AppError::unauthorized(
                "Backend session does not belong to this account.",
            ));
        }

        let expires_at = Utc::now() + chrono::TimeDelta::seconds(BACKEND_SESSION_TTL);
        let response = self.runtime_cache.run(
            backend_session_id,
            &auth_session.account_id,
            expires_at,
            |backend| match backend.run_service_method(service, method, input) {
                Ok(payload) => RpcResponse {
                    payload,
                    is_backend_error: false,
                },
                Err(payload) => RpcResponse {
                    payload,
                    is_backend_error: true,
                },
            },
        )?;

        self.store
            .touch_backend_lease(backend_session_id, expires_at)
            .await?;

        if !response.is_backend_error {
            self.store
                .apply_collection_context_update(
                    backend_session_id,
                    collection_context_update(service, method, input)?,
                    expires_at,
                )
                .await?;
        }

        Ok(response)
    }

    pub async fn purge_expired(&self) -> Result<(), AppError> {
        self.store.purge_expired().await?;
        self.runtime_cache.purge_expired();
        Ok(())
    }
}

#[derive(Default)]
struct BackendRuntimeCache {
    entries: Mutex<HashMap<String, BackendRuntimeEntry>>,
}

impl BackendRuntimeCache {
    fn insert(
        &self,
        session_id: String,
        owner_account_id: String,
        backend: Backend,
        expires_at: DateTime<Utc>,
    ) {
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        entries.insert(
            session_id,
            BackendRuntimeEntry {
                owner_account_id,
                backend,
                expires_at,
            },
        );
    }

    fn remove(&self, session_id: &str) {
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        entries.remove(session_id);
    }

    fn remove_owned_by(&self, account_id: &str) {
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        entries.retain(|_, entry| entry.owner_account_id != account_id);
    }

    fn purge_expired(&self) {
        let now = Utc::now();
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        entries.retain(|_, entry| entry.expires_at > now);
    }

    fn run<T>(
        &self,
        session_id: &str,
        owner_account_id: &str,
        expires_at: DateTime<Utc>,
        run: impl FnOnce(&mut Backend) -> T,
    ) -> Result<T, AppError> {
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let entry = entries
            .get_mut(session_id)
            .ok_or_else(|| AppError::not_found("Backend session was not found."))?;

        if entry.owner_account_id != owner_account_id {
            return Err(AppError::unauthorized(
                "Backend session does not belong to this account.",
            ));
        }

        entry.expires_at = expires_at;
        Ok(run(&mut entry.backend))
    }
}

struct BackendRuntimeEntry {
    owner_account_id: String,
    backend: Backend,
    expires_at: DateTime<Utc>,
}

#[derive(Clone)]
struct RemoteSessionStore {
    pool: PgPool,
}

impl RemoteSessionStore {
    fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    async fn insert_pairing(
        &self,
        pairing_code: &str,
        account_id: &str,
        account_display_name: &str,
        device_name: Option<&str>,
        expires_at: DateTime<Utc>,
    ) -> Result<(), AppError> {
        sqlx::query(
            "INSERT INTO remote_pairings
                (pairing_code_hash, account_id, account_display_name, device_name, expires_at)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(hash_secret(pairing_code))
        .bind(account_id)
        .bind(account_display_name)
        .bind(device_name)
        .bind(expires_at)
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;
        Ok(())
    }

    async fn consume_pairing(&self, pairing_code: &str) -> Result<PairingRow, AppError> {
        let mut transaction = self.pool.begin().await.map_err(AppError::internal)?;
        let pairing = sqlx::query_as::<_, PairingRow>(
            "SELECT account_id, account_display_name, expires_at, consumed_at
             FROM remote_pairings
             WHERE pairing_code_hash = $1
             FOR UPDATE",
        )
        .bind(hash_secret(pairing_code))
        .fetch_optional(&mut *transaction)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::unauthorized("Invalid or expired pairing code."))?;

        if pairing.expires_at <= Utc::now() || pairing.consumed_at.is_some() {
            return Err(AppError::unauthorized("Invalid or expired pairing code."));
        }

        sqlx::query(
            "UPDATE remote_pairings
             SET consumed_at = NOW()
             WHERE pairing_code_hash = $1",
        )
        .bind(hash_secret(pairing_code))
        .execute(&mut *transaction)
        .await
        .map_err(AppError::internal)?;

        transaction.commit().await.map_err(AppError::internal)?;
        Ok(pairing)
    }

    async fn insert_auth_session(&self, issued: &IssuedAuthSession) -> Result<(), AppError> {
        let capabilities =
            serde_json::to_value(&issued.capabilities).map_err(AppError::internal)?;
        sqlx::query(
            "INSERT INTO remote_auth_sessions
                (access_token_hash, refresh_token_hash, account_id, account_display_name,
                 capabilities_json, access_expires_at, refresh_expires_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(hash_secret(&issued.access_token))
        .bind(hash_secret(&issued.refresh_token))
        .bind(&issued.account_id)
        .bind(&issued.account_display_name)
        .bind(capabilities)
        .bind(issued.access_expires_at)
        .bind(issued.refresh_expires_at)
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;
        Ok(())
    }

    async fn auth_session_for_access(
        &self,
        access_token: &str,
    ) -> Result<AuthSessionRecord, AppError> {
        let record = sqlx::query_as::<_, AuthSessionRow>(
            "SELECT account_id, account_display_name, capabilities_json, access_expires_at,
                    refresh_expires_at, revoked_at
             FROM remote_auth_sessions
             WHERE access_token_hash = $1",
        )
        .bind(hash_secret(access_token))
        .fetch_optional(&self.pool)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::unauthorized("Access token is invalid or expired."))?;

        if record.revoked_at.is_some() || record.access_expires_at <= Utc::now() {
            return Err(AppError::unauthorized(
                "Access token is invalid or expired.",
            ));
        }

        record.into_session()
    }

    async fn auth_session_for_refresh(
        &self,
        refresh_token: &str,
    ) -> Result<AuthSessionRecord, AppError> {
        let record = sqlx::query_as::<_, AuthSessionRow>(
            "SELECT account_id, account_display_name, capabilities_json, access_expires_at,
                    refresh_expires_at, revoked_at
             FROM remote_auth_sessions
             WHERE refresh_token_hash = $1",
        )
        .bind(hash_secret(refresh_token))
        .fetch_optional(&self.pool)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::unauthorized("Refresh token is invalid or expired."))?;

        if record.revoked_at.is_some() || record.refresh_expires_at <= Utc::now() {
            return Err(AppError::unauthorized(
                "Refresh token is invalid or expired.",
            ));
        }

        record.into_session()
    }

    async fn rotate_auth_session(
        &self,
        refresh_token: &str,
        issued: &IssuedAuthSession,
    ) -> Result<(), AppError> {
        let capabilities =
            serde_json::to_value(&issued.capabilities).map_err(AppError::internal)?;
        let result = sqlx::query(
            "UPDATE remote_auth_sessions
             SET access_token_hash = $1,
                 refresh_token_hash = $2,
                 capabilities_json = $3,
                 access_expires_at = $4,
                 refresh_expires_at = $5,
                 revoked_at = NULL
             WHERE refresh_token_hash = $6
               AND revoked_at IS NULL",
        )
        .bind(hash_secret(&issued.access_token))
        .bind(hash_secret(&issued.refresh_token))
        .bind(capabilities)
        .bind(issued.access_expires_at)
        .bind(issued.refresh_expires_at)
        .bind(hash_secret(refresh_token))
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;

        if result.rows_affected() == 0 {
            return Err(AppError::unauthorized(
                "Refresh token is invalid or expired.",
            ));
        }

        Ok(())
    }

    async fn revoke_auth_session(
        &self,
        access_token: &str,
        refresh_token: Option<&str>,
    ) -> Result<Vec<String>, AppError> {
        let access_hash = hash_secret(access_token);
        let refresh_hash = refresh_token.map(hash_secret);
        let account_ids = sqlx::query_scalar::<_, String>(
            "SELECT DISTINCT account_id
             FROM remote_auth_sessions
             WHERE access_token_hash = $1
                OR ($2::TEXT IS NOT NULL AND refresh_token_hash = $2)",
        )
        .bind(&access_hash)
        .bind(refresh_hash.as_deref())
        .fetch_all(&self.pool)
        .await
        .map_err(AppError::internal)?;

        if account_ids.is_empty() {
            return Ok(Vec::new());
        }

        sqlx::query(
            "UPDATE remote_auth_sessions
             SET revoked_at = COALESCE(revoked_at, NOW())
             WHERE access_token_hash = $1
                OR ($2::TEXT IS NOT NULL AND refresh_token_hash = $2)",
        )
        .bind(access_hash)
        .bind(refresh_hash.as_deref())
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;

        sqlx::query(
            "UPDATE remote_backend_leases
             SET closed_at = COALESCE(closed_at, NOW())
             WHERE owner_account_id = ANY($1)",
        )
        .bind(&account_ids)
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;

        Ok(account_ids)
    }

    async fn create_backend_lease(
        &self,
        backend_session_id: &str,
        owner_account_id: &str,
        instance_id: &str,
        init_bytes: &[u8],
        expires_at: DateTime<Utc>,
    ) -> Result<(), AppError> {
        sqlx::query(
            "INSERT INTO remote_backend_leases
                (backend_session_id, owner_account_id, instance_id, backend_init_bytes, expires_at)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(backend_session_id)
        .bind(owner_account_id)
        .bind(instance_id)
        .bind(init_bytes)
        .bind(expires_at)
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;
        Ok(())
    }

    async fn active_backend_lease(
        &self,
        backend_session_id: &str,
    ) -> Result<BackendLeaseRow, AppError> {
        let lease = sqlx::query_as::<_, BackendLeaseRow>(
            "SELECT owner_account_id, expires_at, closed_at
             FROM remote_backend_leases
             WHERE backend_session_id = $1",
        )
        .bind(backend_session_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("Backend session was not found."))?;

        if lease.closed_at.is_some() || lease.expires_at <= Utc::now() {
            return Err(AppError::not_found("Backend session was not found."));
        }

        Ok(lease)
    }

    async fn close_backend_lease(&self, backend_session_id: &str) -> Result<(), AppError> {
        sqlx::query(
            "UPDATE remote_backend_leases
             SET closed_at = COALESCE(closed_at, NOW())
             WHERE backend_session_id = $1",
        )
        .bind(backend_session_id)
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;
        Ok(())
    }

    async fn touch_backend_lease(
        &self,
        backend_session_id: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<(), AppError> {
        sqlx::query(
            "UPDATE remote_backend_leases
             SET expires_at = $2,
                 last_seen_at = NOW()
             WHERE backend_session_id = $1
               AND closed_at IS NULL",
        )
        .bind(backend_session_id)
        .bind(expires_at)
        .execute(&self.pool)
        .await
        .map_err(AppError::internal)?;
        Ok(())
    }

    async fn apply_collection_context_update(
        &self,
        backend_session_id: &str,
        update: CollectionContextUpdate,
        expires_at: DateTime<Utc>,
    ) -> Result<(), AppError> {
        match update {
            CollectionContextUpdate::Unchanged => Ok(()),
            CollectionContextUpdate::Opened {
                collection_path,
                media_folder,
                media_db,
            } => {
                sqlx::query(
                    "UPDATE remote_backend_leases
                     SET collection_path = $2,
                         media_folder = $3,
                         media_db = $4,
                         expires_at = $5,
                         last_seen_at = NOW()
                     WHERE backend_session_id = $1
                       AND closed_at IS NULL",
                )
                .bind(backend_session_id)
                .bind(collection_path)
                .bind(media_folder)
                .bind(media_db)
                .bind(expires_at)
                .execute(&self.pool)
                .await
                .map_err(AppError::internal)?;
                Ok(())
            }
            CollectionContextUpdate::Closed => {
                sqlx::query(
                    "UPDATE remote_backend_leases
                     SET collection_path = NULL,
                         media_folder = NULL,
                         media_db = NULL,
                         expires_at = $2,
                         last_seen_at = NOW()
                     WHERE backend_session_id = $1
                       AND closed_at IS NULL",
                )
                .bind(backend_session_id)
                .bind(expires_at)
                .execute(&self.pool)
                .await
                .map_err(AppError::internal)?;
                Ok(())
            }
        }
    }

    async fn purge_expired(&self) -> Result<(), AppError> {
        let mut transaction = self.pool.begin().await.map_err(AppError::internal)?;
        purge_pairings(&mut transaction).await?;
        purge_auth_sessions(&mut transaction).await?;
        purge_backend_leases(&mut transaction).await?;
        transaction.commit().await.map_err(AppError::internal)?;
        Ok(())
    }
}

async fn purge_pairings(transaction: &mut Transaction<'_, Postgres>) -> Result<(), AppError> {
    sqlx::query(
        "DELETE FROM remote_pairings
         WHERE expires_at <= NOW()
            OR consumed_at IS NOT NULL",
    )
    .execute(&mut **transaction)
    .await
    .map_err(AppError::internal)?;
    Ok(())
}

async fn purge_auth_sessions(transaction: &mut Transaction<'_, Postgres>) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE remote_auth_sessions
         SET revoked_at = COALESCE(revoked_at, NOW())
         WHERE revoked_at IS NULL
           AND refresh_expires_at <= NOW()",
    )
    .execute(&mut **transaction)
    .await
    .map_err(AppError::internal)?;
    Ok(())
}

async fn purge_backend_leases(transaction: &mut Transaction<'_, Postgres>) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE remote_backend_leases
         SET closed_at = COALESCE(closed_at, NOW())
         WHERE closed_at IS NULL
           AND expires_at <= NOW()",
    )
    .execute(&mut **transaction)
    .await
    .map_err(AppError::internal)?;
    Ok(())
}

#[derive(FromRow)]
struct PairingRow {
    account_id: String,
    account_display_name: String,
    expires_at: DateTime<Utc>,
    consumed_at: Option<DateTime<Utc>>,
}

#[derive(FromRow)]
struct AuthSessionRow {
    account_id: String,
    account_display_name: String,
    capabilities_json: Value,
    access_expires_at: DateTime<Utc>,
    refresh_expires_at: DateTime<Utc>,
    revoked_at: Option<DateTime<Utc>>,
}

impl AuthSessionRow {
    fn into_session(self) -> Result<AuthSessionRecord, AppError> {
        let capabilities =
            serde_json::from_value(self.capabilities_json).map_err(AppError::internal)?;
        Ok(AuthSessionRecord {
            account_id: self.account_id,
            account_display_name: self.account_display_name,
            refresh_expires_at: self.refresh_expires_at,
            capabilities,
        })
    }
}

#[derive(Clone, FromRow)]
pub struct BackendLeaseRow {
    pub owner_account_id: String,
    pub expires_at: DateTime<Utc>,
    pub closed_at: Option<DateTime<Utc>>,
}

struct IssuedAuthSession {
    access_token: String,
    refresh_token: String,
    account_id: String,
    account_display_name: String,
    access_expires_at: DateTime<Utc>,
    refresh_expires_at: DateTime<Utc>,
    capabilities: CapabilitiesResponse,
}

impl IssuedAuthSession {
    fn new(
        account_id: String,
        account_display_name: String,
        capabilities: CapabilitiesResponse,
    ) -> Self {
        Self {
            access_token: Uuid::new_v4().to_string(),
            refresh_token: Uuid::new_v4().to_string(),
            account_id,
            account_display_name,
            access_expires_at: Utc::now() + chrono::TimeDelta::seconds(ACCESS_TOKEN_TTL),
            refresh_expires_at: Utc::now() + chrono::TimeDelta::seconds(REFRESH_TOKEN_TTL),
            capabilities,
        }
    }

    fn response(&self) -> AuthSessionResponse {
        AuthSessionResponse {
            access_token: self.access_token.clone(),
            refresh_token: self.refresh_token.clone(),
            expires_at: self.access_expires_at.to_rfc3339(),
            account_id: self.account_id.clone(),
            account_display_name: self.account_display_name.clone(),
            capabilities: self.capabilities.clone(),
        }
    }
}

enum CollectionContextUpdate {
    Unchanged,
    Opened {
        collection_path: String,
        media_folder: String,
        media_db: String,
    },
    Closed,
}

fn collection_context_update(
    service: u32,
    method: u32,
    input: &[u8],
) -> Result<CollectionContextUpdate, AppError> {
    if service != 3 {
        return Ok(CollectionContextUpdate::Unchanged);
    }

    match method {
        0 => {
            let request = OpenCollectionRequest::decode(input).map_err(|error| {
                AppError::bad_request(format!("Invalid open collection RPC: {error}"))
            })?;
            Ok(CollectionContextUpdate::Opened {
                collection_path: request.collection_path,
                media_folder: request.media_folder_path,
                media_db: request.media_db_path,
            })
        }
        1 => {
            let _ = CloseCollectionRequest::decode(input).map_err(|error| {
                AppError::bad_request(format!("Invalid close collection RPC: {error}"))
            })?;
            Ok(CollectionContextUpdate::Closed)
        }
        _ => Ok(CollectionContextUpdate::Unchanged),
    }
}

fn hash_secret(secret: &str) -> String {
    let digest = Sha256::digest(secret.as_bytes());
    hex::encode(digest)
}
