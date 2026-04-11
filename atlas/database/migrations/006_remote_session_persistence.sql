CREATE TABLE IF NOT EXISTS remote_pairings (
    pairing_code_hash TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    account_display_name TEXT NOT NULL,
    device_name TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_remote_pairings_expires_at
    ON remote_pairings (expires_at);

CREATE TABLE IF NOT EXISTS remote_auth_sessions (
    access_token_hash TEXT PRIMARY KEY,
    refresh_token_hash TEXT NOT NULL UNIQUE,
    account_id TEXT NOT NULL,
    account_display_name TEXT NOT NULL,
    capabilities_json JSONB NOT NULL,
    access_expires_at TIMESTAMPTZ NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_remote_auth_sessions_refresh
    ON remote_auth_sessions (refresh_token_hash);

CREATE INDEX IF NOT EXISTS idx_remote_auth_sessions_refresh_expires
    ON remote_auth_sessions (refresh_expires_at);

CREATE TABLE IF NOT EXISTS remote_backend_leases (
    backend_session_id TEXT PRIMARY KEY,
    owner_account_id TEXT NOT NULL,
    instance_id TEXT NOT NULL,
    backend_init_bytes BYTEA NOT NULL,
    collection_path TEXT,
    media_folder TEXT,
    media_db TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_remote_backend_leases_owner
    ON remote_backend_leases (owner_account_id);

CREATE INDEX IF NOT EXISTS idx_remote_backend_leases_expires
    ON remote_backend_leases (expires_at);
