# Roadmap: Anki SwiftUI Migration

This roadmap describes the phased migration of Anki from a multi-platform
Python/Qt/Svelte application to a macOS-only SwiftUI app, integrating
anki-atlas analytics and AI capabilities.

See `docs/migration/` for detailed technical documents referenced below.

---

## Phase 0: Documentation and Planning [COMPLETE]

**Goal:** Complete migration documentation before touching code.

**Deliverables:**
- `docs/migration/architecture.md` -- target system architecture
- `docs/migration/stripping-guide.md` -- exact file removal inventory
- `docs/migration/build-migration.md` -- cargo build system migration
- `docs/migration/swift-ffi.md` -- Swift FFI bridge design
- `docs/migration/atlas-integration.md` -- atlas crate integration plan
- `ROADMAP.md` -- this file
- `TODO.md` -- granular task checklist
- Updated `CLAUDE.md` -- project conventions for the new shape

**Milestone:** All documentation reviewed and approved.

---

## Phase 1: Strip and Build [COMPLETE]

**Goal:** Remove all non-Rust code and get a clean `cargo build` working.

**Depends on:** Phase 0

**Steps:**
1. Create a feature branch (`swiftui-migration`)
2. Bulk delete UI layers: `qt/aqt/`, `ts/`, `pylib/`, `python/`
3. Delete root JS/Python config files (package.json, yarn*, pyproject.toml, etc.)
4. Delete CI configs (`.github/`, `.buildkite/`)
5. Remove Python/TypeScript codegen from `rslib/proto/build.rs` and `rslib/i18n/build.rs`
6. Remove Windows-specific Rust code (TTS, error types, launcher)
7. Clean `.cargo/config.toml` (remove DESCRIPTORS_BIN, PROTOC, etc.)
8. Update root `Cargo.toml` (remove non-Rust workspace members and Windows deps)
9. Replace `out/buildhash` dependency with `git rev-parse`
10. Install `protoc` via Homebrew
11. Verify: `cargo check --workspace && cargo test --workspace`

**Reference:** `docs/migration/stripping-guide.md`, `docs/migration/build-migration.md`

**Milestone:** `cargo build --workspace` succeeds with Rust-only codebase.

---

## Phase 2: Swift FFI Bridge [COMPLETE]

**Goal:** Create a minimal bridge that lets Swift code talk to the Rust backend.

**Depends on:** Phase 1

**Steps:**
1. Create `bridge/` crate (`crate-type = ["staticlib"]`)
2. Implement C-ABI functions: `anki_init`, `anki_command`, `anki_free`, `anki_free_buffer`
3. Implement `ByteBuffer` type for owned byte transfer across FFI
4. Add `bridge/` to workspace members
5. Verify `cargo build -p anki_bridge` produces `libanki_bridge.a`
6. Generate Swift protobuf types: `protoc --swift_out=... proto/anki/*.proto`
7. Create Xcode project with bridging header (`AnkiBridge.h`)
8. Implement `AnkiBackend.swift` (C function wrappers)
9. Implement `AnkiService.swift` (async typed interface)
10. Test: initialize Backend and open an Anki collection from SwiftUI

**Reference:** `docs/migration/swift-ffi.md`

**Milestone:** SwiftUI app successfully opens and reads an Anki collection.

---

## Phase 3: Core SwiftUI App [COMPLETE]

**Goal:** Build the essential SRS screens to replace the Qt/Svelte UI.

**Depends on:** Phase 2

**Screens to implement:**
1. **Deck browser** -- list decks with card counts, due counts, new counts
2. **Reviewer** -- display card front/back, answer buttons (Again/Hard/Good/Easy)
3. **Note editor** -- create and edit notes with field-per-notetype layout
4. **Search** -- full-text search with Anki's search syntax
5. **Deck options** -- scheduling parameters (FSRS settings)
6. **Statistics** -- review history charts, forecast
7. **Import/Export** -- .apkg file import and export
8. **Sync** -- AnkiWeb sync with progress indicator
9. **Preferences** -- app settings, collection path

**Milestone:** Fully functional SRS app: review cards, edit notes, search, sync.

---

## Phase 4: Atlas Integration [COMPLETE]

**Goal:** Merge anki-atlas crates into the workspace alongside Anki core.

**Depends on:** Phase 1 (does not require Phase 2/3)

**Steps:**
1. Copy atlas crates into `atlas/` subdirectory
2. Add all atlas crates to workspace `Cargo.toml`
3. Resolve dependency version conflicts (rusqlite, reqwest, strum, phf)
4. Upgrade workspace to Rust edition 2024, toolchain 1.92+
5. Implement `AnkiDataSource` trait to replace `anki-reader`
6. Implement `CollectionSource` adapter using `anki::backend::Backend`
7. Replace Redis job queue with in-process `tokio::mpsc` channels
8. Configure Qdrant for embedded mode (local storage)
9. Decide PostgreSQL strategy (embedded-postgres vs SQLite migration)
10. Wire `surface-runtime` to use `CollectionSource`
11. Verify: `cargo check --workspace && cargo test --workspace`

**Reference:** `docs/migration/atlas-integration.md`

**Milestone:** `cargo build --workspace` succeeds with both Anki + Atlas crates.

---

## Phase 5: Atlas Features in SwiftUI [COMPLETE]

**Goal:** Expose atlas capabilities in the native UI and via MCP.

**Depends on:** Phase 3 + Phase 4

**Features:**
1. **Hybrid search** -- semantic + FTS search with RRF fusion in the search screen
2. **Topic taxonomy browser** -- hierarchical topic tree with coverage metrics
3. **Coverage analytics** -- topic coverage percentages, gap detection
4. **Duplicate detection** -- embedding-based duplicate card finder
5. **LLM card generation** -- generate cards from Obsidian notes or pasted text
6. **Card validation** -- quality scoring and improvement suggestions
7. **Obsidian vault sync** -- import/sync notes from Obsidian vaults
8. **Knowledge graph** -- concept relationship visualization
9. **MCP server** -- `bins/mcp/` binary for Claude Code integration
10. **CLI** -- `bins/cli/` binary for terminal automation

**Milestone:** All atlas features accessible from SwiftUI and MCP.

---

## Phase 6: Polish and Distribution

**Goal:** Package and distribute the macOS application.

**Depends on:** Phase 5

**Steps:**
1. App icon and visual polish
2. macOS app packaging (.dmg installer)
3. Code signing and notarization
4. AGPL-3.0 compliance (source code offer, license display)
5. Evaluate Mac App Store distribution (AGPL compatibility)
6. Performance profiling and optimization
7. Crash reporting and telemetry (opt-in)
8. User documentation / help screens

**Milestone:** Distributable macOS application.

---

## Dependency Graph

```
Phase 0 (Docs)
    |
    v
Phase 1 (Strip & Build)
    |
    ├──────────────┐
    v              v
Phase 2 (FFI)   Phase 4 (Atlas)
    |              |
    v              |
Phase 3 (UI)       |
    |              |
    └──────┬───────┘
           v
    Phase 5 (Atlas UI)
           |
           v
    Phase 6 (Polish)
```

Phases 2/3 and Phase 4 can proceed in parallel after Phase 1.

---

---

# Architecture Improvements

The following phases address structural debt identified across rslib and atlas.
They can proceed independently of the migration phases above, starting any time
after Phase 4 (Atlas Integration) is complete.

```
Phase A (Foundations) ──> Phase B (Decomposition) ──> Phase C (API & Integration)
```

---

## Phase A: Shared Foundations & Type Safety [COMPLETE]

**Goal:** Establish shared abstractions that reduce duplication and improve FFI safety.

**Depends on:** Phase 4 (Atlas Integration)

### A.1 Extract `ffi_common` crate

Unify duplicated FFI utilities from `bridge/` and `atlas_bridge/` into a shared crate.

**Files:**
- `bridge/src/lib.rs` -- ByteBuffer, catch_unwind pattern
- `atlas_bridge/src/lib.rs` -- AtlasByteBuffer, catch_unwind pattern

**Deliverables:**
- New `ffi_common/` crate with:
  - `ByteBuffer` struct (generic, not bridge-specific)
  - `catch_unwind_to_result()` helper returning structured `FfiError`
  - `FfiError` enum: `PanicCaught(String)`, `BadInput(String)`, `NotInitialized`
  - Handle validation wrapper type
- Both bridges refactored to use `ffi_common`
- Zero code duplication between bridge crates

### A.2 Create shared `NoteMetadata` type

Eliminate the 3-way duplication of note fields across atlas crates.

**Current duplication:**
- `indexer/src/service.rs` -- `NoteForIndexing` (9 fields)
- `indexer/src/vector/schema.rs` -- `NotePayload` (16 fields, 7 overlapping)
- `search/src/repository.rs` -- `NoteDetail` (same 7 fields via SQL JOIN)

**Deliverables:**
- New `NoteMetadata` struct in `atlas/common/src/types.rs`:
  ```rust
  pub struct NoteMetadata {
      pub note_id: i64, pub model_id: i64, pub tags: Vec<String>,
      pub deck_names: Vec<String>, pub mature: bool, pub lapses: i32, pub reps: i32,
  }
  ```
- `NoteForIndexing`, `NotePayload`, `NoteDetail` refactored to use `NoteMetadata`
- All tests updated

### A.3 Implement `AnkiDataSource` trait

Replace the stub in `atlas/anki-sync/src/anki_reader.rs` with a working trait.

**Files:**
- `atlas/anki-sync/src/anki_reader.rs` -- stub with TODO comment
- `atlas/anki-sync/src/core.rs` -- sync pipeline

**Deliverables:**
- `AnkiDataSource` trait with methods: `read_decks()`, `read_notes()`, `read_cards()`, `read_card_stats()`
- `SqliteAnkiDataSource` implementation reading from `.anki2` collection files
- `MockAnkiDataSource` for testing
- Integration test: read real collection file -> verify data extraction

### A.4 Shared query builders

Extract duplicated SQL patterns from atlas repositories.

**Current duplication:**
- `search/src/repository.rs` -- note detail LEFT JOIN
- `analytics/src/repository.rs` -- deck names fetch, note excerpt
- `knowledge-graph/src/repository.rs` -- conditional query duplication

**Deliverables:**
- New module `atlas/database/src/queries.rs` with shared functions:
  - `note_details_query()` -- note + cards + decks JOIN
  - `deck_names_for_note()` -- fetch deck names
  - `note_excerpt()` -- fetch normalized_text truncated
- Search, analytics, knowledge-graph refactored to use shared queries
- Conditional query pattern in knowledge-graph fixed (single query with optional WHERE)

**Milestone:** Shared types and utilities in place, zero FFI code duplication.

---

## Phase B: Decompose God Objects [COMPLETE]

**Goal:** Break apart oversized structures for better testability and maintainability.

**Depends on:** Phase A

### B.1 Extract rslib domain services from Collection

Collection has 139 `impl` blocks across 105+ files. Extract focused service objects.

**Steps:**
1. Create `CardService` with `add()`, `update()`, `get()` -- takes `&mut SqliteStorage`
2. Create `NoteService` with `add_note()`, `update_note()`, `prepare_for_update()`
3. Create `DeckService` with `get_or_create()`, `rename()`, `remove()`
4. Keep `Collection` as orchestrator that owns services:
   ```rust
   pub struct Collection {
       pub cards: CardService,
       pub notes: NoteService,
       pub decks: DeckService,
       storage: SqliteStorage,
       // ...
   }
   ```
5. Update `impl Collection` blocks to delegate to services
6. Add unit tests for each service with mock storage

**Impact:** Enables testing individual domains without full Collection setup.

### B.2 Split surface-runtime

`surface-runtime` depends on 11 sibling crates and mixes DI container with
service orchestration (639 lines in one file).

**Steps:**
1. Split `services.rs` into 3 modules:
   - `services.rs` -- `SurfaceServices` struct definition only (~100 lines)
   - `service_facades.rs` -- `SearchFacade`/`AnalyticsFacade` traits + impls (~200 lines)
   - `services_builder.rs` -- `build_surface_services()` factory + config validation (~150 lines)
2. Make all workflow services consistently trait-based:
   - Add `SyncExecutor` trait (currently concrete `Arc<SyncExecutionService>`)
   - Add `PreviewGenerator` trait (currently concrete `Arc<GeneratePreviewService>`)
3. Remove dead code: unused validation functions, `EMBEDDING_VECTOR_SCHEMA` constant

### B.3 Split `atlas/common` into focused crates

Common is a catch-all with config, error, types, and logging mixed together.

**Steps:**
1. Extract `atlas/types/` crate -- `NoteMetadata`, `CardId`, `DeckId`, `Language`, etc.
2. Extract `atlas/config/` crate -- per-domain config structs:
   - `DatabaseConfig`, `JobsConfig`, `EmbeddingsConfig`, `RerankConfig`, `ApiConfig`
   - Each with independent `FromEnv` loading and `validate()` method
3. Keep `atlas/common/` for cross-cutting: error types, logging, macros
4. Create `/docs/CONFIG.md` -- environment variable reference table

### B.4 Add trait abstractions to rslib storage

Storage is accessed directly via `col.storage.get_card()` with no trait boundary.

**Steps:**
1. Define `trait StorageRead` with read-only operations (get_card, get_note, search)
2. Define `trait StorageWrite` extending `StorageRead` with mutations
3. Implement for `SqliteStorage`
4. Use trait bounds in service methods instead of concrete `SqliteStorage`
5. Create `MockStorage` for unit tests

**Milestone:** Core god objects decomposed, testable in isolation.

---

## Phase C: API & Integration Cleanup [COMPLETE]

**Goal:** Clean up proto surface, automate Swift types, document architecture.

**Depends on:** Phase B

### C.1 Proto API cleanup

20 proto files with 38 services, several empty.

**Steps:**
1. Mark empty services with `reserved` declarations and deprecation comments:
   - `SyncService {}`, `LinksService {}`, empty `CardsService` frontend
2. Split `scheduler.proto` (482 lines) into:
   - `scheduler.proto` -- core scheduling types and RPC
   - `scheduler_states.proto` -- state machine types
3. Add doc comments to each service describing its domain
4. Create `PROTO_COMPATIBILITY.md` documenting versioning policy

### C.2 Automate Swift DTO generation

`AtlasDTOs.swift` (356 lines) is manually synchronized with Rust types.

**Steps:**
1. Create `atlas/codegen/` crate with build script that:
   - Reads `surface-contracts` Rust types via `serde` reflection
   - Generates matching Swift `Codable` structs
2. Integrate into Xcode build phase
3. Delete hand-written `AtlasDTOs.swift`
4. Add CI check: regenerate and diff to catch drift

### C.3 Improve error flow across FFI boundaries

Errors crossing FFI lose context: panics become generic strings, HTTP status
codes are erased.

**Steps:**
1. Add structured `FfiError` to bridge responses (from Phase A.1)
2. Add `SurfaceError` variants preserving HTTP status for rerank errors:
   - `RerankTransport(String)`, `RerankHttp { status: u16, body: String }`
3. Swift side: map `FfiError` codes to `AnkiError` cases
4. Add integration tests: trigger Rust error -> verify Swift receives structured error

### C.4 Document crate architecture

No documentation exists for the 41-crate workspace structure.

**Deliverables:**
- `/docs/CRATE_LAYOUT.md` -- dependency graph, layer descriptions, crate purposes
- `/docs/CONFIG.md` -- all environment variables with defaults and descriptions
- `atlas/common/README.md` -- what belongs in common vs. other crates
- CODEOWNERS file mapping crate directories to teams/individuals
- Update `CLAUDE.md` with pointers to new docs

**Milestone:** Clean API surface, automated type generation, documented architecture.

---

## Architecture Improvement Dependency Graph

```
Phase A (Foundations)
  A.1 ffi_common ────────────────────────────────> C.3 Error flow
  A.2 NoteMetadata ──────────────────────────────> B.1 rslib services
  A.3 AnkiDataSource ────────────────────────────> (standalone)
  A.4 Query builders ────────────────────────────> (standalone)
    |
    v
Phase B (Decomposition)
  B.1 Extract rslib services ────────────────────> B.4 Storage traits
  B.2 Split surface-runtime ─────────────────────> (standalone)
  B.3 Split common crate ───────────────────────-> (standalone)
  B.4 Storage trait abstractions ────────────────> (standalone)
    |
    v
Phase C (API & Integration)
  C.1 Proto cleanup ─────────────────────────────> (standalone)
  C.2 Swift DTO codegen ─────────────────────────> (standalone)
  C.3 Error flow ────────────────────────────────> (standalone)
  C.4 Architecture docs ─────────────────────────> (standalone)
```

**Parallelization notes:**
- A.1, A.2, A.3, A.4 can all proceed in parallel
- B.1, B.2, B.3 can proceed in parallel after Phase A completes
- C.1, C.2, C.4 can start any time (no dependencies on B)
- C.3 depends on A.1

---

## Key Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| AGPL + Mac App Store incompatibility | Cannot distribute via App Store | Distribute as .dmg with source offer |
| PostgreSQL too heavy for desktop | Large binary, complex startup | Start with embedded-postgres, migrate to SQLite if needed |
| Dependency version conflicts | Build failures | Resolve in Phase 4, test incrementally |
| Rust edition 2024 upgrade breaks Anki code | Compiler errors | Fix warnings incrementally during Phase 1 |
| Proto API changes in upstream Anki | Fork divergence | Pin to specific Anki commit, cherry-pick selectively |
