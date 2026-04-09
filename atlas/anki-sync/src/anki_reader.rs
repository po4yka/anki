/// Anki SQLite collection reader.
/// Implements `AnkiDataSource` for reading from `.anki2` files.
use chrono::{DateTime, TimeZone, Utc};
use common::{CardId, DeckId, ModelId, NoteId};
use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnkiDeck {
    pub deck_id: DeckId,
    pub name: String,
    pub parent_name: Option<String>,
    pub config: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnkiModel {
    pub model_id: ModelId,
    pub name: String,
    pub fields: Vec<serde_json::Value>,
    pub templates: Vec<serde_json::Value>,
    pub config: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnkiNote {
    pub note_id: NoteId,
    pub model_id: ModelId,
    pub tags: Vec<String>,
    pub fields: Vec<String>,
    pub fields_json: HashMap<String, String>,
    pub raw_fields: Option<String>,
    pub normalized_text: String,
    pub mtime: i64,
    pub usn: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnkiCard {
    pub card_id: CardId,
    pub note_id: NoteId,
    pub deck_id: DeckId,
    pub ord: i32,
    pub due: Option<i32>,
    pub ivl: i32,
    pub ease: i32,
    pub lapses: i32,
    pub reps: i32,
    pub queue: i32,
    pub card_type: i32,
    pub mtime: i64,
    pub usn: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardStats {
    pub card_id: CardId,
    pub reviews: i32,
    pub avg_ease: Option<f64>,
    pub fail_rate: Option<f64>,
    pub last_review_at: Option<DateTime<Utc>>,
    pub total_time_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AnkiCollection {
    pub decks: Vec<AnkiDeck>,
    pub models: Vec<AnkiModel>,
    pub notes: Vec<AnkiNote>,
    pub cards: Vec<AnkiCard>,
    pub card_stats: Vec<CardStats>,
}

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

#[derive(Debug, thiserror::Error)]
pub enum AnkiReaderError {
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("json parse error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("collection not found: {path}")]
    NotFound { path: String },
    #[error("reader error: {0}")]
    Other(String),
}

// ---------------------------------------------------------------------------
// Trait
// ---------------------------------------------------------------------------

/// Trait for reading data from an Anki collection.
#[cfg_attr(test, mockall::automock)]
pub trait AnkiDataSource: Send + Sync {
    fn read_decks(&self) -> Result<Vec<AnkiDeck>, AnkiReaderError>;
    fn read_models(&self) -> Result<Vec<AnkiModel>, AnkiReaderError>;
    fn read_notes(&self) -> Result<Vec<AnkiNote>, AnkiReaderError>;
    fn read_cards(&self) -> Result<Vec<AnkiCard>, AnkiReaderError>;
    fn read_card_stats(&self) -> Result<Vec<CardStats>, AnkiReaderError>;
    fn read_collection(&self) -> Result<AnkiCollection, AnkiReaderError>;
}

// ---------------------------------------------------------------------------
// SQLite implementation
// ---------------------------------------------------------------------------

pub struct SqliteAnkiDataSource {
    path: PathBuf,
}

impl SqliteAnkiDataSource {
    pub fn new(path: impl Into<PathBuf>) -> Result<Self, AnkiReaderError> {
        let path = path.into();
        if !path.exists() {
            return Err(AnkiReaderError::NotFound {
                path: path.display().to_string(),
            });
        }
        Ok(Self { path })
    }

    fn open_connection(&self) -> Result<Connection, AnkiReaderError> {
        Ok(Connection::open_with_flags(
            &self.path,
            OpenFlags::SQLITE_OPEN_READ_ONLY,
        )?)
    }
}

impl AnkiDataSource for SqliteAnkiDataSource {
    fn read_decks(&self) -> Result<Vec<AnkiDeck>, AnkiReaderError> {
        let conn = self.open_connection()?;

        // Try legacy col table first (schema 11), fall back to schema 18+
        let json_result: Result<String, rusqlite::Error> =
            conn.query_row("SELECT decks FROM col", [], |row| row.get(0));

        match json_result {
            Ok(decks_json) => {
                let map: HashMap<String, serde_json::Value> = serde_json::from_str(&decks_json)?;
                let mut decks = Vec::with_capacity(map.len());
                for (id_str, value) in map {
                    let deck_id: i64 = id_str
                        .parse()
                        .map_err(|e| AnkiReaderError::Other(format!("invalid deck id: {e}")))?;
                    let name = value
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    let parent_name = name.rfind("::").map(|pos| name[..pos].to_string());
                    decks.push(AnkiDeck {
                        deck_id: DeckId(deck_id),
                        name,
                        parent_name,
                        config: value,
                    });
                }
                Ok(decks)
            }
            Err(_) => {
                // Schema 18+: decks table with binary protobuf blobs — return empty with a warning.
                // Full schema 18 support requires protobuf decoding; return empty for now.
                Ok(Vec::new())
            }
        }
    }

    fn read_models(&self) -> Result<Vec<AnkiModel>, AnkiReaderError> {
        let conn = self.open_connection()?;

        let json_result: Result<String, rusqlite::Error> =
            conn.query_row("SELECT models FROM col", [], |row| row.get(0));

        match json_result {
            Ok(models_json) => {
                let map: HashMap<String, serde_json::Value> = serde_json::from_str(&models_json)?;
                let mut models = Vec::with_capacity(map.len());
                for (id_str, value) in map {
                    let model_id: i64 = id_str
                        .parse()
                        .map_err(|e| AnkiReaderError::Other(format!("invalid model id: {e}")))?;
                    let name = value
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    let fields = value
                        .get("flds")
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_default();
                    let templates = value
                        .get("tmpls")
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_default();
                    models.push(AnkiModel {
                        model_id: ModelId(model_id),
                        name,
                        fields,
                        templates,
                        config: value,
                    });
                }
                Ok(models)
            }
            Err(_) => {
                // Schema 18+: notetypes table — return empty for now.
                Ok(Vec::new())
            }
        }
    }

    fn read_notes(&self) -> Result<Vec<AnkiNote>, AnkiReaderError> {
        let conn = self.open_connection()?;
        let mut stmt = conn.prepare("SELECT id, mid, tags, flds, mod, usn FROM notes")?;

        let notes = stmt
            .query_map([], |row| {
                let note_id: i64 = row.get(0)?;
                let model_id: i64 = row.get(1)?;
                let tags_str: String = row.get(2)?;
                let flds: String = row.get(3)?;
                let mtime: i64 = row.get(4)?;
                let usn: i32 = row.get(5)?;
                Ok((note_id, model_id, tags_str, flds, mtime, usn))
            })?
            .collect::<Result<Vec<_>, rusqlite::Error>>()?;

        let result = notes
            .into_iter()
            .map(|(note_id, model_id, tags_str, flds, mtime, usn)| {
                let tags: Vec<String> = tags_str
                    .split_whitespace()
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();
                let fields: Vec<String> = flds.split('\x1f').map(|s| s.to_string()).collect();
                let normalized_text = fields.join(" ");
                AnkiNote {
                    note_id: NoteId(note_id),
                    model_id: ModelId(model_id),
                    tags,
                    fields_json: HashMap::new(),
                    raw_fields: Some(flds),
                    normalized_text,
                    fields,
                    mtime,
                    usn,
                }
            })
            .collect();

        Ok(result)
    }

    fn read_cards(&self) -> Result<Vec<AnkiCard>, AnkiReaderError> {
        let conn = self.open_connection()?;
        let mut stmt = conn.prepare(
            "SELECT id, nid, did, ord, due, ivl, factor, lapses, reps, queue, type, mod, usn FROM cards",
        )?;

        let cards = stmt
            .query_map([], |row| {
                let card_id: i64 = row.get(0)?;
                let note_id: i64 = row.get(1)?;
                let deck_id: i64 = row.get(2)?;
                let ord: i32 = row.get(3)?;
                let due: i32 = row.get(4)?;
                let ivl: i32 = row.get(5)?;
                let ease: i32 = row.get(6)?;
                let lapses: i32 = row.get(7)?;
                let reps: i32 = row.get(8)?;
                let queue: i32 = row.get(9)?;
                let card_type: i32 = row.get(10)?;
                let mtime: i64 = row.get(11)?;
                let usn: i32 = row.get(12)?;
                Ok(AnkiCard {
                    card_id: CardId(card_id),
                    note_id: NoteId(note_id),
                    deck_id: DeckId(deck_id),
                    ord,
                    due: if due == 0 { None } else { Some(due) },
                    ivl,
                    ease,
                    lapses,
                    reps,
                    queue,
                    card_type,
                    mtime,
                    usn,
                })
            })?
            .collect::<Result<Vec<_>, rusqlite::Error>>()?;

        Ok(cards)
    }

    fn read_card_stats(&self) -> Result<Vec<CardStats>, AnkiReaderError> {
        let conn = self.open_connection()?;
        let mut stmt = conn.prepare(
            "SELECT cid,
                    COUNT(*) as reviews,
                    AVG(CASE WHEN ease > 0 THEN CAST(ease AS REAL) ELSE NULL END) as avg_ease,
                    CAST(SUM(CASE WHEN ease = 1 THEN 1 ELSE 0 END) AS REAL) / NULLIF(COUNT(*), 0) as fail_rate,
                    MAX(id / 1000) as last_review_ts,
                    SUM(time) as total_time_ms
             FROM revlog
             GROUP BY cid",
        )?;

        let stats = stmt
            .query_map([], |row| {
                let card_id: i64 = row.get(0)?;
                let reviews: i32 = row.get(1)?;
                let avg_ease: Option<f64> = row.get(2)?;
                let fail_rate: Option<f64> = row.get(3)?;
                let last_review_ts: Option<i64> = row.get(4)?;
                let total_time_ms: i64 = row.get(5)?;
                Ok((
                    card_id,
                    reviews,
                    avg_ease,
                    fail_rate,
                    last_review_ts,
                    total_time_ms,
                ))
            })?
            .collect::<Result<Vec<_>, rusqlite::Error>>()?;

        let result = stats
            .into_iter()
            .map(
                |(card_id, reviews, avg_ease, fail_rate, last_review_ts, total_time_ms)| {
                    let last_review_at =
                        last_review_ts.and_then(|ts| Utc.timestamp_opt(ts, 0).single());
                    CardStats {
                        card_id: CardId(card_id),
                        reviews,
                        avg_ease,
                        fail_rate,
                        last_review_at,
                        total_time_ms,
                    }
                },
            )
            .collect();

        Ok(result)
    }

    fn read_collection(&self) -> Result<AnkiCollection, AnkiReaderError> {
        Ok(AnkiCollection {
            decks: self.read_decks()?,
            models: self.read_models()?,
            notes: self.read_notes()?,
            cards: self.read_cards()?,
            card_stats: self.read_card_stats()?,
        })
    }
}

// ---------------------------------------------------------------------------
// Public convenience function
// ---------------------------------------------------------------------------

pub fn read_anki_collection(path: &Path) -> Result<AnkiCollection, AnkiReaderError> {
    let source = SqliteAnkiDataSource::new(path)?;
    source.read_collection()
}

// ---------------------------------------------------------------------------
// Normalizer module (unchanged)
// ---------------------------------------------------------------------------

pub mod normalizer {
    use super::{AnkiCard, AnkiDeck, AnkiNote};
    use common::{DeckId, NoteId};
    use std::collections::HashMap;

    pub fn build_deck_map(decks: &[AnkiDeck]) -> HashMap<DeckId, &AnkiDeck> {
        decks.iter().map(|d| (d.deck_id, d)).collect()
    }

    pub fn build_card_deck_map(cards: &[AnkiCard]) -> HashMap<NoteId, DeckId> {
        cards.iter().map(|c| (c.note_id, c.deck_id)).collect()
    }

    pub fn normalize_notes(
        _notes: &mut Vec<AnkiNote>,
        _deck_map: &HashMap<DeckId, &AnkiDeck>,
        _card_deck_map: &HashMap<NoteId, DeckId>,
    ) {
        // TODO: Replace with AnkiDataSource adapter
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_found_returns_error() {
        let result = SqliteAnkiDataSource::new("/nonexistent/path.anki2");
        assert!(matches!(result, Err(AnkiReaderError::NotFound { .. })));
    }

    #[test]
    fn error_display() {
        let err = AnkiReaderError::NotFound {
            path: "/tmp/test".into(),
        };
        assert!(err.to_string().contains("/tmp/test"));
    }

    #[test]
    fn error_is_send_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<AnkiReaderError>();
    }
}
