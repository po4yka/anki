-- pgvector extension and note chunk embeddings table.
-- HNSW index is created lazily by ensure_collection() once dimension is known.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS note_chunks (
    chunk_id       TEXT PRIMARY KEY,
    note_id        BIGINT NOT NULL REFERENCES notes(note_id) ON DELETE CASCADE,
    chunk_kind     TEXT NOT NULL DEFAULT 'text_primary',
    modality       TEXT NOT NULL DEFAULT 'text',
    source_field   TEXT,
    asset_rel_path TEXT,
    mime_type      TEXT,
    preview_label  TEXT,
    content_hash   TEXT NOT NULL,
    embedding      vector NOT NULL,
    chunk_text     TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_note_chunks_note_id ON note_chunks(note_id);
CREATE INDEX IF NOT EXISTS idx_note_chunks_content_hash ON note_chunks(note_id, content_hash);
CREATE INDEX IF NOT EXISTS idx_note_chunks_fts
    ON note_chunks USING gin(to_tsvector('english', COALESCE(chunk_text, '')));

-- Vector collection metadata (dimension, model fingerprint).
CREATE TABLE IF NOT EXISTS vector_collection_meta (
    key        TEXT PRIMARY KEY,
    value      JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
