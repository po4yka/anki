use sqlx::PgPool;

/// Standard note-cards-decks LEFT JOIN fragment for use in query builders.
pub const NOTE_CARDS_DECKS_JOIN: &str = "LEFT JOIN cards c ON c.note_id = n.note_id \
     LEFT JOIN decks d ON d.deck_id = c.deck_id";

/// Fetch distinct deck names for a given note.
pub async fn deck_names_for_note(pool: &PgPool, note_id: i64) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT DISTINCT d.name FROM cards c \
         JOIN decks d ON d.deck_id = c.deck_id \
         WHERE c.note_id = $1 \
         ORDER BY d.name",
    )
    .bind(note_id)
    .fetch_all(pool)
    .await
}

/// Fetch the full normalized text for a note.
pub async fn note_text(pool: &PgPool, note_id: i64) -> Result<Option<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT normalized_text FROM notes WHERE note_id = $1 AND deleted_at IS NULL",
    )
    .bind(note_id)
    .fetch_optional(pool)
    .await
}

/// Note excerpt (first 200 chars) and tags.
#[derive(Debug, Clone)]
pub struct NoteExcerpt {
    pub excerpt: String,
    pub tags: Vec<String>,
}

/// Fetch a short excerpt and tags for a note.
pub async fn note_excerpt_and_tags(
    pool: &PgPool,
    note_id: i64,
) -> Result<Option<NoteExcerpt>, sqlx::Error> {
    let row: Option<(String, Vec<String>)> = sqlx::query_as(
        "SELECT LEFT(COALESCE(normalized_text, ''), 200), COALESCE(tags, ARRAY[]::text[]) \
         FROM notes WHERE note_id = $1 AND deleted_at IS NULL",
    )
    .bind(note_id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|(excerpt, tags)| NoteExcerpt { excerpt, tags }))
}

/// Fetch the total review count for a note's cards.
pub async fn note_review_count(pool: &PgPool, note_id: i64) -> Result<i64, sqlx::Error> {
    let count: Option<i64> = sqlx::query_scalar(
        "SELECT COALESCE(SUM(cs.reviews), 0) FROM card_stats cs \
         JOIN cards c ON c.card_id = cs.card_id \
         WHERE c.note_id = $1",
    )
    .bind(note_id)
    .fetch_optional(pool)
    .await?;

    Ok(count.unwrap_or(0))
}

/// Batch fetch all active (non-deleted) note IDs.
pub async fn all_active_note_ids(pool: &PgPool) -> Result<Vec<i64>, sqlx::Error> {
    sqlx::query_scalar("SELECT note_id FROM notes WHERE deleted_at IS NULL ORDER BY note_id")
        .fetch_all(pool)
        .await
}
