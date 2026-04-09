use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use async_trait::async_trait;
use rusqlite::Connection;

use indexer::vector::{
    NotePayload, ScoredNote, SearchFilters, SemanticSearchHit, VectorRepository, VectorStoreError,
};

/// SQLite-backed vector repository for mobile/embedded use.
///
/// Stores embeddings as little-endian f32 binary blobs and performs brute-force
/// cosine similarity search. Suitable for collections up to ~100k notes.
pub struct SqliteVectorRepository {
    conn: Mutex<Connection>,
    dimension: Mutex<Option<usize>>,
}

// --- helpers -----------------------------------------------------------------

fn vec_to_blob(v: &[f32]) -> Vec<u8> {
    v.iter().flat_map(|f| f.to_le_bytes()).collect()
}

fn blob_to_vec(blob: &[u8]) -> Vec<f32> {
    blob.chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    let mut dot = 0.0f32;
    let mut norm_a = 0.0f32;
    let mut norm_b = 0.0f32;
    for (x, y) in a.iter().zip(b.iter()) {
        dot += x * y;
        norm_a += x * x;
        norm_b += y * y;
    }
    let denom = norm_a.sqrt() * norm_b.sqrt();
    if denom == 0.0 { 0.0 } else { dot / denom }
}

fn sql_err(e: rusqlite::Error) -> VectorStoreError {
    VectorStoreError::Sql(e.to_string())
}

// --- constructor -------------------------------------------------------------

impl SqliteVectorRepository {
    pub fn new(path: impl Into<PathBuf>) -> Result<Self, VectorStoreError> {
        let path = path.into();
        let conn =
            Connection::open(&path).map_err(|e| VectorStoreError::Connection(e.to_string()))?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
            .map_err(sql_err)?;
        Ok(Self {
            conn: Mutex::new(conn),
            dimension: Mutex::new(None),
        })
    }

    pub fn in_memory() -> Result<Self, VectorStoreError> {
        let conn = Connection::open_in_memory()
            .map_err(|e| VectorStoreError::Connection(e.to_string()))?;
        Ok(Self {
            conn: Mutex::new(conn),
            dimension: Mutex::new(None),
        })
    }

    fn lock(&self) -> Result<std::sync::MutexGuard<'_, Connection>, VectorStoreError> {
        self.conn
            .lock()
            .map_err(|e| VectorStoreError::Client(e.to_string()))
    }

    fn get_cached_dimension(&self) -> Result<Option<usize>, VectorStoreError> {
        self.dimension
            .lock()
            .map(|g| *g)
            .map_err(|e| VectorStoreError::Client(e.to_string()))
    }

    fn set_cached_dimension(&self, dim: Option<usize>) -> Result<(), VectorStoreError> {
        *self
            .dimension
            .lock()
            .map_err(|e| VectorStoreError::Client(e.to_string()))? = dim;
        Ok(())
    }

    fn load_dimension_from_db(conn: &Connection) -> Result<Option<usize>, VectorStoreError> {
        let mut stmt = conn
            .prepare("SELECT value FROM vector_meta WHERE key = 'dimension'")
            .map_err(sql_err)?;
        let mut rows = stmt
            .query_map([], |row| row.get::<_, i64>(0))
            .map_err(sql_err)?;
        match rows.next() {
            Some(Ok(v)) => Ok(Some(v as usize)),
            Some(Err(e)) => Err(sql_err(e)),
            None => Ok(None),
        }
    }

    fn create_schema(conn: &Connection, dimension: usize) -> Result<(), VectorStoreError> {
        conn.execute_batch(&format!(
            "CREATE TABLE IF NOT EXISTS vector_meta (
                key   TEXT PRIMARY KEY,
                value INTEGER NOT NULL
            );
            INSERT OR REPLACE INTO vector_meta (key, value) VALUES ('dimension', {dimension});
            CREATE TABLE IF NOT EXISTS note_chunks (
                chunk_id        TEXT PRIMARY KEY,
                note_id         INTEGER NOT NULL,
                chunk_kind      TEXT NOT NULL DEFAULT 'text_primary',
                modality        TEXT NOT NULL DEFAULT 'text',
                source_field    TEXT,
                asset_rel_path  TEXT,
                mime_type       TEXT,
                preview_label   TEXT,
                content_hash    TEXT NOT NULL,
                embedding       BLOB NOT NULL,
                chunk_text      TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_note_chunks_note_id ON note_chunks(note_id);"
        ))
        .map_err(sql_err)
    }
}

// --- trait impl --------------------------------------------------------------

#[async_trait]
impl VectorRepository for SqliteVectorRepository {
    async fn ensure_collection(&self, dimension: usize) -> Result<bool, VectorStoreError> {
        if let Some(cached) = self.get_cached_dimension()? {
            if cached == dimension {
                return Ok(false);
            }
            return Err(VectorStoreError::DimensionMismatch {
                expected: cached,
                actual: dimension,
            });
        }

        let conn = self.lock()?;
        // Check if already stored in DB.
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS vector_meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL);",
        )
        .map_err(sql_err)?;

        match Self::load_dimension_from_db(&conn)? {
            Some(d) if d == dimension => {
                self.set_cached_dimension(Some(d))?;
                Ok(false)
            }
            Some(d) => Err(VectorStoreError::DimensionMismatch {
                expected: d,
                actual: dimension,
            }),
            None => {
                Self::create_schema(&conn, dimension)?;
                self.set_cached_dimension(Some(dimension))?;
                Ok(true)
            }
        }
    }

    async fn collection_dimension(&self) -> Result<Option<usize>, VectorStoreError> {
        if let Some(d) = self.get_cached_dimension()? {
            return Ok(Some(d));
        }
        let conn = self.lock()?;
        // vector_meta may not exist yet.
        let exists: bool = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='vector_meta'",
                [],
                |r| r.get::<_, i64>(0),
            )
            .map(|n| n > 0)
            .map_err(sql_err)?;
        if !exists {
            return Ok(None);
        }
        Self::load_dimension_from_db(&conn)
    }

    async fn recreate_collection(&self, dimension: usize) -> Result<(), VectorStoreError> {
        let conn = self.lock()?;
        conn.execute_batch(
            "DELETE FROM note_chunks;
             DELETE FROM vector_meta;",
        )
        .map_err(sql_err)?;
        conn.execute(
            "INSERT OR REPLACE INTO vector_meta (key, value) VALUES ('dimension', ?1)",
            [dimension as i64],
        )
        .map_err(sql_err)?;
        self.set_cached_dimension(Some(dimension))
    }

    async fn upsert_vectors(
        &self,
        vectors: &[Vec<f32>],
        payloads: &[NotePayload],
    ) -> Result<usize, VectorStoreError> {
        if vectors.len() != payloads.len() {
            return Err(VectorStoreError::Client(
                "vectors and payloads length mismatch".into(),
            ));
        }
        if vectors.is_empty() {
            return Ok(0);
        }

        let conn = self.lock()?;
        let mut stmt = conn
            .prepare(
                "INSERT OR REPLACE INTO note_chunks
                 (chunk_id, note_id, chunk_kind, modality, source_field,
                  asset_rel_path, mime_type, preview_label, content_hash, embedding, chunk_text)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)",
            )
            .map_err(sql_err)?;

        let mut count = 0usize;
        for (v, p) in vectors.iter().zip(payloads.iter()) {
            let blob = vec_to_blob(v);
            stmt.execute(rusqlite::params![
                p.chunk_id,
                p.meta.note_id,
                p.chunk_kind,
                p.modality,
                p.source_field,
                p.asset_rel_path,
                p.mime_type,
                p.preview_label,
                p.content_hash,
                blob,
                p.preview_label, // chunk_text falls back to preview_label (matches pgvector impl)
            ])
            .map_err(sql_err)?;
            count += 1;
        }
        Ok(count)
    }

    async fn delete_vectors(&self, note_ids: &[i64]) -> Result<usize, VectorStoreError> {
        if note_ids.is_empty() {
            return Ok(0);
        }
        let conn = self.lock()?;
        let placeholders: String = note_ids
            .iter()
            .enumerate()
            .map(|(i, _)| format!("?{}", i + 1))
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!("DELETE FROM note_chunks WHERE note_id IN ({placeholders})");
        let params: Vec<&dyn rusqlite::types::ToSql> = note_ids
            .iter()
            .map(|id| id as &dyn rusqlite::types::ToSql)
            .collect();
        let n = conn.execute(&sql, params.as_slice()).map_err(sql_err)?;
        Ok(n)
    }

    async fn get_existing_hashes(
        &self,
        note_ids: &[i64],
    ) -> Result<HashMap<i64, String>, VectorStoreError> {
        if note_ids.is_empty() {
            return Ok(HashMap::new());
        }
        let conn = self.lock()?;
        let placeholders: String = note_ids
            .iter()
            .enumerate()
            .map(|(i, _)| format!("?{}", i + 1))
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            "SELECT note_id, content_hash FROM note_chunks WHERE note_id IN ({placeholders}) GROUP BY note_id"
        );
        let params: Vec<&dyn rusqlite::types::ToSql> = note_ids
            .iter()
            .map(|id| id as &dyn rusqlite::types::ToSql)
            .collect();
        let mut stmt = conn.prepare(&sql).map_err(sql_err)?;
        let rows = stmt
            .query_map(params.as_slice(), |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(sql_err)?;
        let mut map = HashMap::new();
        for r in rows {
            let (nid, hash) = r.map_err(sql_err)?;
            map.insert(nid, hash);
        }
        Ok(map)
    }

    async fn search_chunks(
        &self,
        query_vector: &[f32],
        _query_text: Option<&str>,
        limit: usize,
        _filters: &SearchFilters,
    ) -> Result<Vec<SemanticSearchHit>, VectorStoreError> {
        let conn = self.lock()?;
        let mut stmt = conn
            .prepare(
                "SELECT chunk_id, note_id, chunk_kind, modality,
                        source_field, asset_rel_path, mime_type, preview_label, embedding
                 FROM note_chunks",
            )
            .map_err(sql_err)?;

        struct Row {
            chunk_id: String,
            note_id: i64,
            chunk_kind: String,
            modality: String,
            source_field: Option<String>,
            asset_rel_path: Option<String>,
            mime_type: Option<String>,
            preview_label: Option<String>,
            score: f32,
        }

        let mut results: Vec<Row> = stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<String>>(7)?,
                    row.get::<_, Vec<u8>>(8)?,
                ))
            })
            .map_err(sql_err)?
            .filter_map(|r| r.ok())
            .map(
                |(
                    chunk_id,
                    note_id,
                    chunk_kind,
                    modality,
                    source_field,
                    asset_rel_path,
                    mime_type,
                    preview_label,
                    blob,
                )| {
                    let embedding = blob_to_vec(&blob);
                    let score = cosine_similarity(query_vector, &embedding);
                    Row {
                        chunk_id,
                        note_id,
                        chunk_kind,
                        modality,
                        source_field,
                        asset_rel_path,
                        mime_type,
                        preview_label,
                        score,
                    }
                },
            )
            .collect();

        results.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(limit);

        Ok(results
            .into_iter()
            .map(|r| SemanticSearchHit {
                note_id: r.note_id,
                chunk_id: r.chunk_id,
                chunk_kind: r.chunk_kind,
                modality: r.modality,
                source_field: r.source_field,
                asset_rel_path: r.asset_rel_path,
                mime_type: r.mime_type,
                preview_label: r.preview_label,
                score: r.score,
            })
            .collect())
    }

    async fn find_similar_to_note(
        &self,
        note_id: i64,
        limit: usize,
        min_score: f32,
        deck_names: Option<&[String]>,
        tags: Option<&[String]>,
    ) -> Result<Vec<ScoredNote>, VectorStoreError> {
        let embedding: Vec<f32> = {
            let conn = self.lock()?;
            let blob: Option<Vec<u8>> = conn
                .query_row(
                    "SELECT embedding FROM note_chunks WHERE note_id = ?1 AND chunk_kind = 'text_primary' LIMIT 1",
                    [note_id],
                    |r| r.get(0),
                )
                .map(Some)
                .or_else(|e| match e {
                    rusqlite::Error::QueryReturnedNoRows => Ok(None),
                    e => Err(e),
                })
                .map_err(sql_err)?;
            match blob {
                Some(b) => blob_to_vec(&b),
                None => {
                    return Err(VectorStoreError::Client(format!(
                        "no embedding found for note {note_id}"
                    )));
                }
            }
        };

        let filters = SearchFilters {
            deck_names: deck_names.map(|d| d.to_vec()),
            tags: tags.map(|t| t.to_vec()),
            ..Default::default()
        };

        let hits = self
            .search_chunks(&embedding, None, limit + 1, &filters)
            .await?;

        let results: Vec<ScoredNote> = hits
            .into_iter()
            .filter(|h| h.note_id != note_id && h.score >= min_score)
            .take(limit)
            .map(|h| ScoredNote {
                note_id: h.note_id,
                score: h.score,
            })
            .collect();

        Ok(results)
    }

    async fn close(&self) -> Result<(), VectorStoreError> {
        Ok(())
    }
}

// --- tests -------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use common::NoteMetadata;

    fn make_payload(note_id: i64, chunk_id: &str, hash: &str) -> NotePayload {
        NotePayload {
            meta: NoteMetadata {
                note_id,
                ..Default::default()
            },
            content_hash: hash.into(),
            chunk_id: chunk_id.into(),
            chunk_kind: "text_primary".into(),
            modality: "text".into(),
            source_field: None,
            asset_rel_path: None,
            mime_type: None,
            preview_label: None,
            fail_rate: None,
        }
    }

    #[tokio::test]
    async fn test_ensure_collection_creates_once() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        let created = repo.ensure_collection(4).await.unwrap();
        assert!(created);
        let created = repo.ensure_collection(4).await.unwrap();
        assert!(!created);
    }

    #[tokio::test]
    async fn test_ensure_collection_dimension_mismatch() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        repo.ensure_collection(4).await.unwrap();
        let err = repo.ensure_collection(8).await.unwrap_err();
        assert!(matches!(err, VectorStoreError::DimensionMismatch { .. }));
    }

    #[tokio::test]
    async fn test_collection_dimension() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        assert_eq!(repo.collection_dimension().await.unwrap(), None);
        repo.ensure_collection(3).await.unwrap();
        assert_eq!(repo.collection_dimension().await.unwrap(), Some(3));
    }

    #[tokio::test]
    async fn test_upsert_and_search() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        repo.ensure_collection(3).await.unwrap();

        let vectors = vec![vec![1.0f32, 0.0, 0.0], vec![0.0, 1.0, 0.0]];
        let payloads = vec![
            make_payload(1, "1:text", "h1"),
            make_payload(2, "2:text", "h2"),
        ];
        let n = repo.upsert_vectors(&vectors, &payloads).await.unwrap();
        assert_eq!(n, 2);

        let results = repo
            .search_chunks(&[1.0, 0.0, 0.0], None, 2, &SearchFilters::default())
            .await
            .unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].note_id, 1);
    }

    #[tokio::test]
    async fn test_delete_vectors() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        repo.ensure_collection(3).await.unwrap();

        let vectors = vec![vec![1.0f32, 0.0, 0.0]];
        let payloads = vec![make_payload(1, "1:text", "h1")];
        repo.upsert_vectors(&vectors, &payloads).await.unwrap();

        let deleted = repo.delete_vectors(&[1]).await.unwrap();
        assert_eq!(deleted, 1);

        let results = repo
            .search_chunks(&[1.0, 0.0, 0.0], None, 10, &SearchFilters::default())
            .await
            .unwrap();
        assert!(results.is_empty());
    }

    #[tokio::test]
    async fn test_get_existing_hashes() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        repo.ensure_collection(3).await.unwrap();

        let vectors = vec![vec![1.0f32, 0.0, 0.0], vec![0.0, 1.0, 0.0]];
        let payloads = vec![
            make_payload(1, "1:text", "hash_one"),
            make_payload(2, "2:text", "hash_two"),
        ];
        repo.upsert_vectors(&vectors, &payloads).await.unwrap();

        let hashes = repo.get_existing_hashes(&[1, 2, 99]).await.unwrap();
        assert_eq!(hashes.get(&1).map(|s| s.as_str()), Some("hash_one"));
        assert_eq!(hashes.get(&2).map(|s| s.as_str()), Some("hash_two"));
        assert!(!hashes.contains_key(&99));
    }

    #[tokio::test]
    async fn test_cosine_similarity_values() {
        assert!((cosine_similarity(&[1.0, 0.0], &[1.0, 0.0]) - 1.0).abs() < 1e-6);
        assert!((cosine_similarity(&[1.0, 0.0], &[0.0, 1.0]) - 0.0).abs() < 1e-6);
        assert!(cosine_similarity(&[0.0, 0.0], &[1.0, 0.0]).abs() < 1e-6);
    }

    #[tokio::test]
    async fn test_recreate_collection() {
        let repo = SqliteVectorRepository::in_memory().unwrap();
        repo.ensure_collection(3).await.unwrap();
        let vectors = vec![vec![1.0f32, 0.0, 0.0]];
        let payloads = vec![make_payload(1, "1:text", "h1")];
        repo.upsert_vectors(&vectors, &payloads).await.unwrap();

        repo.recreate_collection(3).await.unwrap();

        let results = repo
            .search_chunks(&[1.0, 0.0, 0.0], None, 10, &SearchFilters::default())
            .await
            .unwrap();
        assert!(results.is_empty());
    }
}
