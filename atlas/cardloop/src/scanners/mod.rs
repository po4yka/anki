pub mod audit;
pub mod fsrs;
pub mod generation;
pub mod llm_review;
pub mod stale;

use sha2::{Digest, Sha256};

use crate::error::CardloopError;
use crate::models::WorkItem;

/// Generate a deterministic ID for deduplication from a prefix, slug and discriminator.
///
/// Returns the first 16 hex chars of SHA-256(prefix + slug + ":" + discriminator).
/// Pass an empty discriminator to hash only prefix + slug.
pub fn work_item_id(prefix: &str, slug: &str, discriminator: &str) -> String {
    let mut hasher = Sha256::new();
    if !prefix.is_empty() {
        hasher.update(prefix.as_bytes());
    }
    hasher.update(slug.as_bytes());
    if !discriminator.is_empty() {
        hasher.update(b":");
        hasher.update(discriminator.as_bytes());
    }
    let hash = hasher.finalize();
    hash.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// Trait for scanners that detect work items.
///
/// Scanners run single-threaded in the CLI, so no Send + Sync bound.
pub trait Scanner {
    /// Scan the data source and return new or updated work items.
    fn scan(&self, scan_number: u32) -> Result<Vec<WorkItem>, CardloopError>;
}

/// Trait for async scanners that detect work items.
#[cfg_attr(test, mockall::automock)]
#[async_trait::async_trait]
pub trait AsyncScanner: Send + Sync {
    /// Scan the data source and return new or updated work items.
    async fn scan(&self, scan_number: u32) -> Result<Vec<WorkItem>, CardloopError>;
}
