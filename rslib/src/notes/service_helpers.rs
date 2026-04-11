// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Standalone note operations that don't require a full Collection context.
//! These enable testing note logic independently of Collection state.

use crate::notes::Note;
use crate::prelude::*;
use crate::storage::SqliteStorage;

/// Fetch a note by ID, returning an error if not found.
#[allow(dead_code)]
pub(crate) fn get_note_or_error(storage: &SqliteStorage, id: NoteId) -> Result<Note> {
    storage.get_note(id)?.or_not_found(id)
}

/// Check if a note is orphaned (has no cards).
#[allow(dead_code)]
pub(crate) fn is_orphaned(storage: &SqliteStorage, nid: NoteId) -> Result<bool> {
    storage.note_is_orphaned(nid)
}

/// Get the first field of a note as a summary string (truncated to max_len chars).
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn note_summary(note: &Note, max_len: usize) -> String {
    let field = note.fields().first().map(|f| f.as_str()).unwrap_or("");
    if field.len() <= max_len {
        field.to_string()
    } else {
        format!("{}...", &field[..max_len])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_note_with_fields(fields: Vec<&str>) -> Note {
        Note::new_from_storage(
            NoteId(1),
            String::new(),
            NotetypeId(1),
            crate::timestamp::TimestampSecs(0),
            crate::types::Usn(0),
            vec![],
            fields.into_iter().map(|s| s.to_string()).collect(),
            None,
            None,
        )
    }

    #[test]
    fn note_summary_short_field_returned_as_is() {
        let note = make_note_with_fields(vec!["hello"]);
        assert_eq!(note_summary(&note, 10), "hello");
    }

    #[test]
    fn note_summary_long_field_is_truncated() {
        let note = make_note_with_fields(vec!["hello world"]);
        assert_eq!(note_summary(&note, 5), "hello...");
    }

    #[test]
    fn note_summary_exact_max_len_not_truncated() {
        let note = make_note_with_fields(vec!["hello"]);
        assert_eq!(note_summary(&note, 5), "hello");
    }

    #[test]
    fn note_summary_empty_fields_returns_empty() {
        let note = make_note_with_fields(vec![]);
        assert_eq!(note_summary(&note, 10), "");
    }
}
