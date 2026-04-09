// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Standalone card operations that don't require a full Collection context.
//! These enable testing card logic independently of Collection state.

use crate::card::Card;
use crate::notes::NoteId;
use crate::prelude::*;
use crate::storage::SqliteStorage;

/// Fetch a card by ID, returning an error if not found.
pub(crate) fn get_card_or_error(storage: &SqliteStorage, id: CardId) -> Result<Card> {
    storage.get_card(id)?.or_not_found(id)
}

/// Fetch all cards belonging to a note.
pub(crate) fn cards_of_note(storage: &SqliteStorage, nid: NoteId) -> Result<Vec<Card>> {
    storage.all_cards_of_note(nid)
}

/// Check if a card's ease factor is valid (>= 1300 for review cards, or 0 for new).
pub(crate) fn validate_ease_factor(card: &Card) -> bool {
    card.ease_factor == 0 || card.ease_factor >= 1300
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ease_factor_zero_is_valid() {
        // New cards have ease_factor = 0
        let mut card = Card::default();
        card.ease_factor = 0;
        assert!(validate_ease_factor(&card));
    }

    #[test]
    fn ease_factor_below_1300_is_invalid() {
        let mut card = Card::default();
        card.ease_factor = 1200;
        assert!(!validate_ease_factor(&card));
    }

    #[test]
    fn ease_factor_at_1300_is_valid() {
        let mut card = Card::default();
        card.ease_factor = 1300;
        assert!(validate_ease_factor(&card));
    }

    #[test]
    fn ease_factor_above_1300_is_valid() {
        let mut card = Card::default();
        card.ease_factor = 2500;
        assert!(validate_ease_factor(&card));
    }
}
