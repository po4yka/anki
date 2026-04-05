# Roadmap: Anki SwiftUI Migration

This roadmap describes the phased migration of Anki from a multi-platform
Python/Qt/Svelte application to a macOS-only SwiftUI app, integrating
anki-atlas analytics and AI capabilities.

See `docs/migration/` for detailed technical documents referenced below.

---

## Phase 0: Documentation and Planning

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

## Phase 1: Strip and Build

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

## Phase 2: Swift FFI Bridge

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

## Phase 3: Core SwiftUI App

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

## Phase 4: Atlas Integration

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

## Phase 5: Atlas Features in SwiftUI

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

## Key Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| AGPL + Mac App Store incompatibility | Cannot distribute via App Store | Distribute as .dmg with source offer |
| PostgreSQL too heavy for desktop | Large binary, complex startup | Start with embedded-postgres, migrate to SQLite if needed |
| Dependency version conflicts | Build failures | Resolve in Phase 4, test incrementally |
| Rust edition 2024 upgrade breaks Anki code | Compiler errors | Fix warnings incrementally during Phase 1 |
| Proto API changes in upstream Anki | Fork divergence | Pin to specific Anki commit, cherry-pick selectively |
