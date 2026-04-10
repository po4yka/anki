# Atlas Integration

## Overview

The `atlas/` crates provide AI-powered analytics, hybrid search, embeddings,
and LLM-based card generation. They integrate with the Anki core via trait-based
dependency injection.

## Architecture

```
AnkiService -> surface-runtime -> { search, analytics, generator }
                    |
              AnkiDataSource (trait)
                    |
              CollectionSource (adapter)
                    |
                  rslib
```

## Key Components

### AnkiDataSource Trait

Defines the contract between atlas and rslib:

```rust
pub trait AnkiDataSource: Send + Sync {
    fn get_notes(&self, query: &str) -> Result<Vec<Note>>;
    fn get_cards_for_note(&self, note_id: NoteId) -> Result<Vec<Card>>;
    // ...
}
```

### CollectionSource Adapter

Implements `AnkiDataSource` by wrapping an rslib `Collection`:

```rust
pub struct CollectionSource {
    col: Arc<Mutex<Collection>>,
}

impl AnkiDataSource for CollectionSource { ... }
```

### surface-runtime Facade

Single entry point that wires together all atlas services:

```rust
pub struct SurfaceRuntime {
    search: SearchService,
    analytics: AnalyticsService,
    generator: GeneratorService,
}
```

## Infrastructure Choices

- **Job queue**: In-process task queue, not Redis
- **Vector store**: Embedded Qdrant (not external service)
- **All types**: Must be `Send + Sync`
- **Error handling**: `thiserror` for typed errors
- **Tracing**: `#[instrument]` on public async functions
- **Shared state**: `Arc<T>`, never `Rc<T>`

## When to Use

- Adding new atlas services or capabilities
- Modifying the data flow between rslib and atlas
- Understanding how AI features connect to the core
