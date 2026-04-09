use std::collections::HashMap;

use async_trait::async_trait;
use pgvector::Vector;
use sqlx::PgPool;
use tracing::instrument;

use indexer::vector::{
    NotePayload, ScoredNote, SearchFilters, SemanticSearchHit, VectorRepository, VectorStoreError,
};

/// pgvector-backed implementation of [`VectorRepository`].
///
/// Stores embeddings in the `note_chunks` table and uses PostgreSQL FTS
/// for hybrid search via RRF (Reciprocal Rank Fusion).
pub struct PgVectorRepository {
    pool: PgPool,
    dimension: tokio::sync::RwLock<Option<usize>>,
}

impl PgVectorRepository {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            dimension: tokio::sync::RwLock::new(None),
        }
    }

    /// Get the cached dimension or load it from the database.
    async fn get_dimension(&self) -> Result<Option<usize>, VectorStoreError> {
        let cached = *self.dimension.read().await;
        if cached.is_some() {
            return Ok(cached);
        }
        let dim = self.load_dimension().await?;
        if dim.is_some() {
            *self.dimension.write().await = dim;
        }
        Ok(dim)
    }

    async fn load_dimension(&self) -> Result<Option<usize>, VectorStoreError> {
        let row: Option<(serde_json::Value,)> =
            sqlx::query_as("SELECT value FROM vector_collection_meta WHERE key = 'dimension'")
                .fetch_optional(&self.pool)
                .await
                .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        match row {
            Some((val,)) => {
                let dim = val
                    .as_u64()
                    .ok_or_else(|| VectorStoreError::Sql("invalid dimension value".into()))?
                    as usize;
                Ok(Some(dim))
            }
            None => Ok(None),
        }
    }

    async fn store_dimension(&self, dimension: usize) -> Result<(), VectorStoreError> {
        sqlx::query(
            "INSERT INTO vector_collection_meta (key, value) VALUES ('dimension', $1::jsonb)
             ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()",
        )
        .bind(serde_json::json!(dimension))
        .execute(&self.pool)
        .await
        .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        *self.dimension.write().await = Some(dimension);
        Ok(())
    }

    async fn create_hnsw_index(&self, dimension: usize) -> Result<(), VectorStoreError> {
        let sql = format!(
            "CREATE INDEX IF NOT EXISTS idx_note_chunks_embedding_hnsw \
             ON note_chunks USING hnsw ((embedding::vector({dimension})) vector_cosine_ops) \
             WITH (m = 16, ef_construction = 200)"
        );
        sqlx::query(&sql)
            .execute(&self.pool)
            .await
            .map_err(|e| VectorStoreError::Sql(e.to_string()))?;
        Ok(())
    }

    /// Build dynamic WHERE clause fragments for search filters.
    /// Returns (clause_string, bind_values) where clause_string uses
    /// placeholder markers for binding.
    fn build_filter_sql(filters: &SearchFilters) -> (String, FilterBindings) {
        let mut conditions = Vec::new();
        let mut bindings = FilterBindings::default();

        if let Some(ref deck_names) = filters.deck_names {
            if !deck_names.is_empty() {
                conditions.push(
                    "EXISTS (SELECT 1 FROM cards c JOIN decks d ON d.deck_id = c.deck_id \
                     WHERE c.note_id = nc.note_id AND d.name = ANY($deck_names))"
                        .to_string(),
                );
                bindings.deck_names = Some(deck_names.clone());
            }
        }

        if let Some(ref deck_names_exclude) = filters.deck_names_exclude {
            if !deck_names_exclude.is_empty() {
                conditions.push(
                    "NOT EXISTS (SELECT 1 FROM cards c JOIN decks d ON d.deck_id = c.deck_id \
                     WHERE c.note_id = nc.note_id AND d.name = ANY($deck_names_exclude))"
                        .to_string(),
                );
                bindings.deck_names_exclude = Some(deck_names_exclude.clone());
            }
        }

        if let Some(ref tags) = filters.tags {
            if !tags.is_empty() {
                conditions.push(
                    "EXISTS (SELECT 1 FROM notes n WHERE n.note_id = nc.note_id AND n.tags && $tags)"
                        .to_string(),
                );
                bindings.tags = Some(tags.clone());
            }
        }

        if let Some(ref tags_exclude) = filters.tags_exclude {
            if !tags_exclude.is_empty() {
                conditions.push(
                    "NOT EXISTS (SELECT 1 FROM notes n WHERE n.note_id = nc.note_id AND n.tags && $tags_exclude)"
                        .to_string(),
                );
                bindings.tags_exclude = Some(tags_exclude.clone());
            }
        }

        if let Some(ref model_ids) = filters.model_ids {
            if !model_ids.is_empty() {
                conditions.push(
                    "EXISTS (SELECT 1 FROM notes n WHERE n.note_id = nc.note_id AND n.model_id = ANY($model_ids))"
                        .to_string(),
                );
                bindings.model_ids = Some(model_ids.clone());
            }
        }

        if filters.mature_only {
            conditions.push(
                "EXISTS (SELECT 1 FROM cards c WHERE c.note_id = nc.note_id AND c.ivl >= 21)"
                    .to_string(),
            );
        }

        if let Some(min_reps) = filters.min_reps {
            conditions.push(
                "EXISTS (SELECT 1 FROM cards c WHERE c.note_id = nc.note_id AND c.reps >= $min_reps)"
                    .to_string(),
            );
            bindings.min_reps = Some(min_reps);
        }

        if let Some(max_lapses) = filters.max_lapses {
            conditions.push(
                "EXISTS (SELECT 1 FROM cards c WHERE c.note_id = nc.note_id AND c.lapses <= $max_lapses)"
                    .to_string(),
            );
            bindings.max_lapses = Some(max_lapses);
        }

        let clause = if conditions.is_empty() {
            "TRUE".to_string()
        } else {
            conditions.join(" AND ")
        };

        (clause, bindings)
    }
}

#[derive(Default)]
struct FilterBindings {
    deck_names: Option<Vec<String>>,
    deck_names_exclude: Option<Vec<String>>,
    tags: Option<Vec<String>>,
    tags_exclude: Option<Vec<String>>,
    model_ids: Option<Vec<i64>>,
    min_reps: Option<i32>,
    max_lapses: Option<i32>,
}

/// Execute a semantic-only or hybrid (semantic + FTS) search query.
///
/// This function builds the SQL dynamically because:
/// - Filter conditions are optional and variable
/// - The vector dimension must be embedded in casts
/// - Hybrid mode adds FTS CTEs only when query_text is present
async fn execute_search(
    pool: &PgPool,
    query_vector: &[f32],
    query_text: Option<&str>,
    limit: usize,
    filters: &SearchFilters,
    dimension: usize,
    exclude_note_id: Option<i64>,
) -> Result<Vec<SemanticSearchHit>, VectorStoreError> {
    let (filter_clause, bindings) = PgVectorRepository::build_filter_sql(filters);

    let exclude_clause = if exclude_note_id.is_some() {
        " AND nc.note_id != $exclude_note_id"
    } else {
        ""
    };

    let vec = Vector::from(query_vector.to_vec());
    let prefetch_limit = (limit * 3) as i64;
    let limit_i64 = limit as i64;

    // Build the query depending on whether we have text for hybrid search.
    let use_hybrid = query_text.is_some_and(|t| !t.trim().is_empty());

    let sql = if use_hybrid {
        format!(
            "WITH semantic AS ( \
                SELECT nc.chunk_id, nc.note_id, nc.chunk_kind, nc.modality, \
                       nc.source_field, nc.asset_rel_path, nc.mime_type, nc.preview_label, \
                       1.0 - (nc.embedding::vector({dimension}) <=> $1::vector({dimension})) AS score, \
                       ROW_NUMBER() OVER (ORDER BY nc.embedding::vector({dimension}) <=> $1::vector({dimension})) AS rank \
                FROM note_chunks nc \
                WHERE {filter_clause}{exclude_clause} \
                ORDER BY nc.embedding::vector({dimension}) <=> $1::vector({dimension}) \
                LIMIT $2 \
            ), \
            fts AS ( \
                SELECT nc.chunk_id, nc.note_id, \
                       ts_rank(to_tsvector('english', COALESCE(nc.chunk_text, '')), \
                               plainto_tsquery('english', $3)) AS score, \
                       ROW_NUMBER() OVER (ORDER BY ts_rank(to_tsvector('english', COALESCE(nc.chunk_text, '')), \
                               plainto_tsquery('english', $3)) DESC) AS rank \
                FROM note_chunks nc \
                WHERE to_tsvector('english', COALESCE(nc.chunk_text, '')) @@ plainto_tsquery('english', $3) \
                      AND {filter_clause}{exclude_clause} \
                LIMIT $2 \
            ), \
            rrf AS ( \
                SELECT COALESCE(s.chunk_id, f.chunk_id) AS chunk_id, \
                       COALESCE(1.0 / (60 + s.rank), 0) + COALESCE(1.0 / (60 + f.rank), 0) AS rrf_score \
                FROM semantic s FULL OUTER JOIN fts f ON s.chunk_id = f.chunk_id \
            ) \
            SELECT r.chunk_id, nc.note_id, r.rrf_score AS score, \
                   nc.chunk_kind, nc.modality, nc.source_field, \
                   nc.asset_rel_path, nc.mime_type, nc.preview_label \
            FROM rrf r JOIN note_chunks nc ON nc.chunk_id = r.chunk_id \
            ORDER BY r.rrf_score DESC LIMIT $4"
        )
    } else {
        format!(
            "SELECT nc.chunk_id, nc.note_id, \
                    1.0 - (nc.embedding::vector({dimension}) <=> $1::vector({dimension})) AS score, \
                    nc.chunk_kind, nc.modality, nc.source_field, \
                    nc.asset_rel_path, nc.mime_type, nc.preview_label \
             FROM note_chunks nc \
             WHERE {filter_clause}{exclude_clause} \
             ORDER BY nc.embedding::vector({dimension}) <=> $1::vector({dimension}) \
             LIMIT $4"
        )
    };

    // We use raw SQL with manual binding since the query is dynamic.
    // Bind positions: $1 = vector, $2 = prefetch_limit, $3 = query_text, $4 = limit
    // Additional filter bindings use named placeholders that we replace.
    let mut final_sql = sql;

    // Replace named filter placeholders with positional params.
    // We start from $5 to avoid collisions.
    let mut param_idx = 5u32;
    let mut replace_and_advance = |placeholder: &str| -> String {
        let pos = format!("${param_idx}");
        param_idx += 1;
        final_sql = final_sql.replace(placeholder, &pos);
        pos
    };

    // Process filter placeholders in order.
    let deck_names_pos = bindings
        .deck_names
        .as_ref()
        .map(|_| replace_and_advance("$deck_names"));
    let deck_names_exclude_pos = bindings
        .deck_names_exclude
        .as_ref()
        .map(|_| replace_and_advance("$deck_names_exclude"));
    let tags_pos = bindings.tags.as_ref().map(|_| replace_and_advance("$tags"));
    let tags_exclude_pos = bindings
        .tags_exclude
        .as_ref()
        .map(|_| replace_and_advance("$tags_exclude"));
    let model_ids_pos = bindings
        .model_ids
        .as_ref()
        .map(|_| replace_and_advance("$model_ids"));
    let min_reps_pos = bindings.min_reps.map(|_| replace_and_advance("$min_reps"));
    let max_lapses_pos = bindings
        .max_lapses
        .map(|_| replace_and_advance("$max_lapses"));
    let exclude_note_pos = exclude_note_id.map(|_| replace_and_advance("$exclude_note_id"));

    // Build query with bindings.
    let mut query = sqlx::query_as::<_, SearchRow>(&final_sql)
        .bind(&vec) // $1
        .bind(prefetch_limit) // $2
        .bind(query_text.unwrap_or("")) // $3
        .bind(limit_i64); // $4

    if let Some(ref vals) = bindings.deck_names {
        let _ = deck_names_pos;
        query = query.bind(vals);
    }
    if let Some(ref vals) = bindings.deck_names_exclude {
        let _ = deck_names_exclude_pos;
        query = query.bind(vals);
    }
    if let Some(ref vals) = bindings.tags {
        let _ = tags_pos;
        query = query.bind(vals);
    }
    if let Some(ref vals) = bindings.tags_exclude {
        let _ = tags_exclude_pos;
        query = query.bind(vals);
    }
    if let Some(ref vals) = bindings.model_ids {
        let _ = model_ids_pos;
        query = query.bind(vals);
    }
    if let Some(val) = bindings.min_reps {
        let _ = min_reps_pos;
        query = query.bind(val);
    }
    if let Some(val) = bindings.max_lapses {
        let _ = max_lapses_pos;
        query = query.bind(val);
    }
    if let Some(val) = exclude_note_id {
        let _ = exclude_note_pos;
        query = query.bind(val);
    }

    let rows = query
        .fetch_all(pool)
        .await
        .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

    Ok(rows
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
            score: r.score as f32,
        })
        .collect())
}

#[derive(sqlx::FromRow)]
struct SearchRow {
    chunk_id: String,
    note_id: i64,
    score: f64,
    chunk_kind: String,
    modality: String,
    source_field: Option<String>,
    asset_rel_path: Option<String>,
    mime_type: Option<String>,
    preview_label: Option<String>,
}

#[async_trait]
impl VectorRepository for PgVectorRepository {
    #[instrument(skip(self))]
    async fn ensure_collection(&self, dimension: usize) -> Result<bool, VectorStoreError> {
        let existing = self.get_dimension().await?;
        match existing {
            Some(d) if d == dimension => Ok(false),
            Some(d) => Err(VectorStoreError::DimensionMismatch {
                expected: d,
                actual: dimension,
            }),
            None => {
                self.store_dimension(dimension).await?;
                self.create_hnsw_index(dimension).await?;
                Ok(true)
            }
        }
    }

    async fn collection_dimension(&self) -> Result<Option<usize>, VectorStoreError> {
        self.get_dimension().await
    }

    #[instrument(skip(self))]
    async fn recreate_collection(&self, dimension: usize) -> Result<(), VectorStoreError> {
        sqlx::query("TRUNCATE note_chunks")
            .execute(&self.pool)
            .await
            .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        sqlx::query("DROP INDEX IF EXISTS idx_note_chunks_embedding_hnsw")
            .execute(&self.pool)
            .await
            .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        self.store_dimension(dimension).await?;
        self.create_hnsw_index(dimension).await?;
        Ok(())
    }

    #[instrument(skip(self, vectors, payloads), fields(count = vectors.len()))]
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

        let mut total = 0usize;
        let batch_size = 200;

        for batch_start in (0..vectors.len()).step_by(batch_size) {
            let batch_end = (batch_start + batch_size).min(vectors.len());
            let mut query_builder = sqlx::QueryBuilder::new(
                "INSERT INTO note_chunks (chunk_id, note_id, chunk_kind, modality, \
                 source_field, asset_rel_path, mime_type, preview_label, \
                 content_hash, embedding, chunk_text) ",
            );

            query_builder.push_values(batch_start..batch_end, |mut b, idx| {
                let p = &payloads[idx];
                let v = Vector::from(vectors[idx].clone());
                b.push_bind(p.chunk_id.clone())
                    .push_bind(p.meta.note_id)
                    .push_bind(p.chunk_kind.clone())
                    .push_bind(p.modality.clone())
                    .push_bind(p.source_field.clone())
                    .push_bind(p.asset_rel_path.clone())
                    .push_bind(p.mime_type.clone())
                    .push_bind(p.preview_label.clone())
                    .push_bind(p.content_hash.clone())
                    .push_bind(v)
                    .push_bind(p.preview_label.clone());
            });

            query_builder.push(
                " ON CONFLICT (chunk_id) DO UPDATE SET \
                 note_id = EXCLUDED.note_id, \
                 chunk_kind = EXCLUDED.chunk_kind, \
                 modality = EXCLUDED.modality, \
                 source_field = EXCLUDED.source_field, \
                 asset_rel_path = EXCLUDED.asset_rel_path, \
                 mime_type = EXCLUDED.mime_type, \
                 preview_label = EXCLUDED.preview_label, \
                 content_hash = EXCLUDED.content_hash, \
                 embedding = EXCLUDED.embedding, \
                 chunk_text = EXCLUDED.chunk_text, \
                 updated_at = NOW()",
            );

            let result = query_builder
                .build()
                .execute(&self.pool)
                .await
                .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

            total += result.rows_affected() as usize;
        }

        Ok(total)
    }

    #[instrument(skip(self))]
    async fn delete_vectors(&self, note_ids: &[i64]) -> Result<usize, VectorStoreError> {
        let result = sqlx::query("DELETE FROM note_chunks WHERE note_id = ANY($1)")
            .bind(note_ids)
            .execute(&self.pool)
            .await
            .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        Ok(result.rows_affected() as usize)
    }

    async fn get_existing_hashes(
        &self,
        note_ids: &[i64],
    ) -> Result<HashMap<i64, String>, VectorStoreError> {
        let rows: Vec<(i64, String)> = sqlx::query_as(
            "SELECT DISTINCT ON (note_id) note_id, content_hash \
             FROM note_chunks WHERE note_id = ANY($1)",
        )
        .bind(note_ids)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        Ok(rows.into_iter().collect())
    }

    #[instrument(skip(self, query_vector))]
    async fn search_chunks(
        &self,
        query_vector: &[f32],
        query_text: Option<&str>,
        limit: usize,
        filters: &SearchFilters,
    ) -> Result<Vec<SemanticSearchHit>, VectorStoreError> {
        let dimension = self
            .get_dimension()
            .await?
            .ok_or_else(|| VectorStoreError::Client("collection not initialized".into()))?;

        execute_search(
            &self.pool,
            query_vector,
            query_text,
            limit,
            filters,
            dimension,
            None,
        )
        .await
    }

    #[instrument(skip(self))]
    async fn find_similar_to_note(
        &self,
        note_id: i64,
        limit: usize,
        min_score: f32,
        deck_names: Option<&[String]>,
        tags: Option<&[String]>,
    ) -> Result<Vec<ScoredNote>, VectorStoreError> {
        let dimension = self
            .get_dimension()
            .await?
            .ok_or_else(|| VectorStoreError::Client("collection not initialized".into()))?;

        // Fetch the primary text chunk embedding for this note.
        let row: Option<(Vector,)> = sqlx::query_as(
            "SELECT embedding FROM note_chunks \
             WHERE note_id = $1 AND chunk_kind = 'text_primary' \
             LIMIT 1",
        )
        .bind(note_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| VectorStoreError::Sql(e.to_string()))?;

        let (embedding,) = row.ok_or_else(|| {
            VectorStoreError::Client(format!("no embedding found for note {note_id}"))
        })?;

        let query_vector: Vec<f32> = embedding.into();

        let filters = SearchFilters {
            deck_names: deck_names.map(|d| d.to_vec()),
            tags: tags.map(|t| t.to_vec()),
            ..Default::default()
        };

        let hits = execute_search(
            &self.pool,
            &query_vector,
            None,
            limit + 1, // +1 to account for self-match exclusion
            &filters,
            dimension,
            Some(note_id),
        )
        .await?;

        let results: Vec<ScoredNote> = hits
            .into_iter()
            .filter(|h| h.score >= min_score)
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
