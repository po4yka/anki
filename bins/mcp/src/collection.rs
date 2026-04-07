use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anki::collection::{Collection, CollectionBuilder};

pub struct CollectionFacade {
    col: Arc<Mutex<Option<Collection>>>,
    col_path: PathBuf,
}

impl CollectionFacade {
    pub fn new(col_path: PathBuf) -> Self {
        Self {
            col: Arc::new(Mutex::new(None)),
            col_path,
        }
    }

    pub async fn with_col<F, T>(&self, func: F) -> Result<T, String>
    where
        F: FnOnce(&mut Collection) -> Result<T, anki::error::AnkiError> + Send + 'static,
        T: Send + 'static,
    {
        let col_arc = self.col.clone();
        let col_path = self.col_path.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = col_arc.lock().map_err(|e| format!("mutex poisoned: {e}"))?;
            if guard.is_none() {
                let col = CollectionBuilder::new(&col_path).build().map_err(|e| {
                    format!("failed to open collection at {}: {e}", col_path.display())
                })?;
                *guard = Some(col);
            }
            let col = guard.as_mut().unwrap();
            func(col).map_err(|e| e.to_string())
        })
        .await
        .map_err(|e| format!("task panicked: {e}"))?
    }
}

impl Drop for CollectionFacade {
    fn drop(&mut self) {
        if let Ok(mut guard) = self.col.lock() {
            drop(guard.take());
        }
    }
}
