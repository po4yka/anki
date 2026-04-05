/// Stub module replacing the removed `anki-reader` crate.
/// These types will be replaced by the `AnkiDataSource` trait adapter in a subsequent migration step.
use chrono::{DateTime, Utc};
use common::{CardId, DeckId, NoteId};
use serde::{Deserialize, Serialize};

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnkiCollection {
    pub cards: Vec<AnkiCard>,
    pub card_stats: Vec<CardStats>,
}

pub fn read_anki_collection(
    _path: &std::path::Path,
) -> Result<AnkiCollection, Box<dyn std::error::Error + Send + Sync>> {
    // TODO: Replace with AnkiDataSource trait adapter
    Err("anki-reader not available; use AnkiDataSource adapter".into())
}

pub mod models {
    pub use super::{AnkiCard, AnkiCollection, CardStats};
}
