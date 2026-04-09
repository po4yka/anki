/// Anki collection reader for cardloop — delegates to `anki-sync`.
pub use anki_sync::anki_reader::{AnkiCard, CardStats, read_anki_collection};

pub mod models {
    pub use super::{AnkiCard, CardStats};
}
