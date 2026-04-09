// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Standalone deck operations that don't require a full Collection context.
//! These enable testing deck logic independently of Collection state.

use crate::decks::Deck;
use crate::prelude::*;
use crate::storage::SqliteStorage;

/// Fetch a deck by ID, returning an error if not found.
pub(crate) fn get_deck_or_error(storage: &SqliteStorage, id: DeckId) -> Result<Deck> {
    storage.get_deck(id)?.or_not_found(id)
}

/// Get all child deck IDs for a parent deck.
pub(crate) fn child_deck_ids(storage: &SqliteStorage, parent: &Deck) -> Result<Vec<DeckId>> {
    storage.deck_id_with_children(parent)
}

/// Check if a deck has no cards.
pub(crate) fn is_empty(storage: &SqliteStorage, did: DeckId) -> Result<bool> {
    storage.deck_is_empty(did)
}
