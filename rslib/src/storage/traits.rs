// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Trait abstractions for the storage layer.
//!
//! These traits define the read-only interface for common storage operations,
//! enabling future testing with mock implementations and alternative backends.
//! Currently only the most-used methods per entity are covered.

use std::collections::HashSet;

use crate::prelude::*;
use crate::storage::SqliteStorage;

/// Read-only storage operations for cards.
pub(crate) trait CardStorageRead {
    fn get_card(&self, id: CardId) -> Result<Option<Card>>;
    fn get_all_card_ids(&self) -> Result<HashSet<CardId>>;
}

/// Read-only storage operations for notes.
pub(crate) trait NoteStorageRead {
    fn get_note(&self, id: NoteId) -> Result<Option<Note>>;
}

/// Read-only storage operations for decks.
pub(crate) trait DeckStorageRead {
    fn get_deck(&self, id: DeckId) -> Result<Option<Deck>>;
    fn get_all_deck_names(&self) -> Result<Vec<(DeckId, String)>>;
}

impl CardStorageRead for SqliteStorage {
    fn get_card(&self, id: CardId) -> Result<Option<Card>> {
        self.get_card(id)
    }

    fn get_all_card_ids(&self) -> Result<HashSet<CardId>> {
        self.get_all_card_ids()
    }
}

impl NoteStorageRead for SqliteStorage {
    fn get_note(&self, id: NoteId) -> Result<Option<Note>> {
        self.get_note(id)
    }
}

impl DeckStorageRead for SqliteStorage {
    fn get_deck(&self, id: DeckId) -> Result<Option<Deck>> {
        self.get_deck(id)
    }

    fn get_all_deck_names(&self) -> Result<Vec<(DeckId, String)>> {
        self.get_all_deck_names()
    }
}
