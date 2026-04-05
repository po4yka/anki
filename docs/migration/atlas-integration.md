# Atlas Integration Guide

This document describes how to integrate anki-atlas crates into the Anki workspace.

## Overview

anki-atlas is a Rust workspace (edition 2024, MSRV 1.88, MIT) containing 21 library crates and 5 binaries covering analytics, search, and LLM card generation. The integration goal is to copy atlas crates into an `atlas/` subdirectory of the Anki workspace, resolve dependency conflicts, and wire them to use Anki's `Collection` directly instead of reading SQLite independently.

## 1. Integration Strategy

Copy atlas crates directly into the Anki workspace (not as a submodule). This gives a unified `Cargo.toml`, shared dependency versions, and easier cross-crate refactoring without submodule sync overhead.

### Directory Layout

After copying, the atlas crates live under `atlas/`:

```
atlas/
├── common/            # Config, shared types, errors, AnkiDataSource trait
├── card/              # Card domain model, slugs
├── taxonomy/          # Tag normalization and validation
├── database/          # PostgreSQL schema (sqlx)
├── anki-sync/         # Sync state tracking
├── indexer/           # Embeddings + Qdrant
├── search/            # Hybrid FTS + semantic search
├── analytics/         # Coverage, gaps, duplicates
├── validation/        # Card quality pipeline
├── generator/         # LLM card generation
├── llm/               # LLM provider abstraction
├── rag/               # RAG service
├── ingest/            # PDF/web ingestion
├── obsidian/          # Vault sync
├── knowledge-graph/   # Concept/topic edges
├── cardloop/          # FSRS feedback loop
├── jobs/              # Job queue (replace Redis with in-process)
├── surface-contracts/ # Shared DTOs
└── surface-runtime/   # Service facade
```

### What Is NOT Copied

| Crate/Binary | Reason |
|---|---|
| `anki-reader` | Replaced by direct `anki` crate dependency via adapter trait |
| `perf-support` | Testing-only utility, not needed in production workspace |
| `api` binary | Server-only; not relevant for desktop |
| `worker` binary | Server-only; not relevant for desktop |
| `perf-harness` binary | Benchmarking only; not needed in workspace |

Binaries that ARE kept:

| Binary | Location | Purpose |
|---|---|---|
| `cli` | `bins/cli/` | Automation scripting |
| `mcp` | `bins/mcp/` | Claude Code MCP server integration |

## 2. Dependency Conflicts

Resolve all conflicts by upgrading to the higher version. Where Cargo allows multiple versions of the same crate (no C FFI linkage issues), note the resolution approach.

| Dependency | Anki version | Atlas version | Resolution |
|---|---|---|---|
| `rusqlite` | 0.36.0 | 0.32.x | Upgrade atlas crates to 0.36 |
| `reqwest` | 0.12.20 | 0.13.x | Upgrade Anki to 0.13, or keep both (Cargo allows multiple reqwest versions if no C linkage conflict) |
| `strum` | 0.27.1 | 0.28.x | Upgrade Anki to 0.28 |
| `phf` | 0.11.3 | 0.13.x | Upgrade Anki to 0.13 |
| `serde` | 1.0.219 | 1.0.x | Compatible (semver minor); no change needed |
| `tokio` | 1.45 | 1.x | Compatible; no change needed |
| `prost` | 0.13 | N/A | Atlas does not use prost; no conflict |
| `fsrs` | 5.2.0 | 5.2.x | Compatible; no change needed |

### Rust Edition Upgrade

Anki currently uses Rust edition 2021 at the workspace level. Atlas uses edition 2024. Upgrade the workspace to edition 2024:

```toml
# Cargo.toml (workspace root)
[workspace.package]
edition = "2024"
```

Edition is per-crate; individual crates can still declare their own edition, but setting the workspace default to 2024 avoids having to override it in every new atlas crate. Existing Anki crates that have `edition = "2021"` explicitly will continue to work.

Toolchain requirement: 1.88 or later (satisfies both Anki's current requirement and Atlas's MSRV 1.88).

## 3. Replacing anki-reader

### Current State

`anki-reader` opens a copy of the Anki SQLite file (copied to avoid locking), reads `notes`, `cards`, `decks`, `models`, and `revlog` tables, normalizes text, and builds in-memory representations. It duplicates what rslib's `Collection` and `SqliteStorage` already do, with less fidelity, and pays the cost of file copying on every read.

### Solution: Adapter Trait

Define a trait in `atlas/common` that atlas crates depend on. Implement the trait using the `anki` crate's backend. This keeps the dependency one-directional: atlas crates depend on the trait, not on rslib directly.

**Trait definition** (`atlas/common/src/anki_source.rs`):

```rust
pub trait AnkiDataSource: Send + Sync {
    async fn get_notes(&self) -> Result<Vec<AtlasNote>>;
    async fn get_cards(&self) -> Result<Vec<AtlasCard>>;
    async fn get_decks(&self) -> Result<Vec<AtlasDeck>>;
    async fn get_revlog(&self) -> Result<Vec<AtlasRevlogEntry>>;
}
```

**Adapter implementation** (`atlas/common/src/anki_collection_source.rs`):

```rust
pub struct CollectionSource {
    backend: anki::backend::Backend,
}

impl AnkiDataSource for CollectionSource {
    async fn get_notes(&self) -> Result<Vec<AtlasNote>> {
        // Call backend.run_service_method() to fetch notes via the protobuf RPC
        // Convert anki_proto::notes::Note -> AtlasNote
        todo!()
    }

    async fn get_cards(&self) -> Result<Vec<AtlasCard>> {
        todo!()
    }

    async fn get_decks(&self) -> Result<Vec<AtlasDeck>> {
        todo!()
    }

    async fn get_revlog(&self) -> Result<Vec<AtlasRevlogEntry>> {
        todo!()
    }
}
```

Conversion logic lives in `atlas/card/src/from_proto.rs` and similar per-crate files, implementing `From<anki_proto::...::T>` for each atlas domain type.

## 4. Crate-by-Crate Integration Plan

| Atlas Crate | Change Needed | Depends on Anki? |
|---|---|---|
| `common` | Add `AnkiDataSource` trait + `CollectionSource` impl | No (defines trait) |
| `card` | Add `From<anki_proto::cards::Card>` and related impls | Proto types only |
| `taxonomy` | No changes | No |
| `database` | No changes (PostgreSQL schema unrelated to Anki) | No |
| `anki-sync` | Replace anki-reader dependency with `AnkiDataSource` | Via trait |
| `indexer` | No changes | No |
| `search` | No changes | No |
| `analytics` | No changes | No |
| `validation` | No changes | No |
| `generator` | No changes | No |
| `llm` | No changes | No |
| `rag` | No changes | No |
| `ingest` | No changes | No |
| `obsidian` | No changes | No |
| `knowledge-graph` | No changes | No |
| `cardloop` | No changes | No |
| `jobs` | Replace Redis backend with in-process queue (see section 5) | No |
| `surface-contracts` | No changes | No |
| `surface-runtime` | Use `CollectionSource`, adapt service wiring | Yes (via trait) |

## 5. Infrastructure Adaptation for Desktop

### Redis -> In-Process Job Queue

Atlas uses Redis for async job dispatch (sync, indexing). For the desktop integration, replace this with an in-process channel-based queue.

Add `InMemoryJobManager` to `atlas/jobs/src/in_memory.rs`:

```rust
pub struct InMemoryJobManager {
    sender: tokio::sync::mpsc::Sender<Job>,
    receiver: Arc<Mutex<tokio::sync::mpsc::Receiver<Job>>>,
    results: Arc<DashMap<JobId, JobResult>>,
}

impl JobManager for InMemoryJobManager {
    async fn enqueue(&self, job: Job) -> Result<JobId> {
        let id = JobId::new();
        self.sender.send(job).await?;
        Ok(id)
    }

    async fn poll(&self, id: JobId) -> Result<JobStatus> {
        match self.results.get(&id) {
            Some(r) => Ok(r.status()),
            None => Ok(JobStatus::Pending),
        }
    }

    async fn cancel(&self, id: JobId) -> Result<()> {
        self.results.insert(id, JobResult::cancelled());
        Ok(())
    }
}
```

Feature-gate the Redis backend so it only compiles for server deployments:

```toml
# atlas/jobs/Cargo.toml
[features]
default = []
redis = ["dep:redis", "dep:deadpool-redis"]
```

Production server code enables the `redis` feature. Desktop uses the default in-memory path.

### Qdrant: Embedded vs. Subprocess

Qdrant supports local storage. For desktop, two options:

1. **Subprocess**: bundle the qdrant binary and spawn it on a local port. The `indexer` crate connects to it as normal via `qdrant-client`. Port is chosen dynamically to avoid conflicts.
2. **Embedded storage via qdrant-client embedded feature**: no subprocess, but requires linking the Qdrant C++ library.

Start with the subprocess approach: simpler linking, well-tested code path in the indexer, and the binary can be distributed alongside Anki.

Vector operations in `atlas/indexer` work identically in both cases; only the connection setup differs.

### PostgreSQL for Desktop

Three options, each with tradeoffs:

| Option | Pros | Cons |
|---|---|---|
| **A: Embedded PostgreSQL** (`embedded-postgres` crate) | Full Postgres compatibility, no schema changes to atlas | 100MB+ binary size, complex startup/shutdown lifecycle |
| **B: SQLite migration** | Lightweight, single-file, familiar to Anki codebase | Significant rewrite of sqlx queries; loses `pg_trgm` and GIN index features |
| **C: External PostgreSQL** | Standard Postgres, no code changes | User must install and configure Postgres separately |

**Recommended path:** Start with Option A (embedded-postgres) to validate the full integration end-to-end without any schema changes. Once integration is confirmed working, evaluate binary size. If size is a blocker, migrate atlas schema to SQLite (Option B) using `sqlx`'s SQLite driver.

## 6. Workspace Cargo.toml Changes

Add atlas members and binaries to the workspace `members` list:

```toml
[workspace]
members = [
    # Anki core
    "rslib",
    "rslib/i18n",
    "rslib/io",
    "rslib/process",
    "rslib/proto",
    "rslib/proto_gen",
    # Bridge
    "bridge",
    # Atlas crates
    "atlas/common",
    "atlas/card",
    "atlas/taxonomy",
    "atlas/database",
    "atlas/anki-sync",
    "atlas/indexer",
    "atlas/search",
    "atlas/analytics",
    "atlas/validation",
    "atlas/generator",
    "atlas/llm",
    "atlas/rag",
    "atlas/ingest",
    "atlas/obsidian",
    "atlas/knowledge-graph",
    "atlas/cardloop",
    "atlas/jobs",
    "atlas/surface-contracts",
    "atlas/surface-runtime",
    # Binaries
    "bins/mcp",
    "bins/cli",
]
```

Add resolved dependency versions to `[workspace.dependencies]` as each conflict is fixed. Atlas crates should reference workspace dependencies via `dep.workspace = true` to keep versions centralized.

## 7. MCP Binary for Claude Code

The MCP server (`bins/mcp/`) runs as a separate process that Claude Code spawns via stdio. It does not link into the Anki Qt application.

Responsibilities:
- Initialize Anki `Backend` with the user's collection path
- Initialize Atlas `SurfaceServices` with `CollectionSource`
- Expose atlas tools: search, analytics, generate, validate, sync
- Expose Anki-specific tools: open collection, get scheduler state, browse notes

The binary is the only place where `CollectionSource` is constructed. All other code interacts through the `AnkiDataSource` trait.

## 8. Testing Strategy

```bash
# Check the full workspace compiles
cargo check --workspace

# Run unit tests for atlas crates, excluding those that need Docker infrastructure
cargo test --workspace \
    --exclude database \
    --exclude anki-sync

# Run the AnkiDataSource adapter unit tests
cargo test -p common -- anki_source

# Full integration test (requires PostgreSQL and Qdrant via Docker)
docker compose -f atlas/infra/docker-compose.yml up -d
cargo test --workspace
```

Tests for `database` and `anki-sync` require Docker because they exercise live PostgreSQL queries. All other atlas crates are self-contained.

## 9. Migration Order

Perform steps in this order. Each step should leave the workspace in a compilable state before proceeding.

1. Copy atlas crates into `atlas/` subdirectory.
2. Add atlas crates and binaries to workspace `Cargo.toml` members list.
3. Resolve dependency version conflicts (upgrade rusqlite, strum, phf in atlas; upgrade reqwest in Anki; upgrade workspace edition to 2024).
4. Run `cargo check --workspace` and fix all compile errors introduced by the version upgrades.
5. Define `AnkiDataSource` trait in `atlas/common/src/anki_source.rs`.
6. Implement `CollectionSource` in `atlas/common/src/anki_collection_source.rs`.
7. Replace all `anki-reader` references in atlas crates with the `AnkiDataSource` trait.
8. Implement `InMemoryJobManager` in `atlas/jobs/src/in_memory.rs` and feature-gate the Redis backend.
9. Wire `surface-runtime` to construct and use `CollectionSource`.
10. Run `cargo test --workspace --exclude database --exclude anki-sync` and fix failures.
11. Wire the MCP binary (`bins/mcp/`) to initialize both Backend and SurfaceServices.
12. Run the full test suite including Docker infrastructure.
