mod repository;
mod schema;

#[cfg(test)]
pub use repository::MockVectorRepository;
pub use repository::VectorRepository;
pub use schema::{
    NotePayload, ScoredNote, SearchFilters, SemanticSearchHit, UpsertResult, VectorStoreError,
};
