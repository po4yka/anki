/// Stub module replacing the removed `anki-reader` crate.
/// These types will be replaced by the `AnkiDataSource` trait adapter in a subsequent migration step.
use chrono::{DateTime, Utc};
use common::{CardId, DeckId, ModelId, NoteId};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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

pub fn read_anki_collection(
    _path: &std::path::Path,
) -> Result<AnkiCollection, Box<dyn std::error::Error + Send + Sync>> {
    // TODO: Replace with AnkiDataSource trait adapter
    Err("anki-reader not available; use AnkiDataSource adapter".into())
}

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
