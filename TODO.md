# TODO: Anki SwiftUI Migration

Granular task checklist derived from ROADMAP.md. Each item is sized for
one work session. Check off items as completed.

---

## Phase 0: Documentation

- [x] Create `docs/migration/` directory
- [x] Write `docs/migration/architecture.md`
- [x] Write `docs/migration/stripping-guide.md`
- [x] Write `docs/migration/build-migration.md`
- [x] Write `docs/migration/swift-ffi.md`
- [x] Write `docs/migration/atlas-integration.md`
- [x] Write `ROADMAP.md`
- [x] Write `TODO.md` (this file)
- [x] Update `CLAUDE.md` for new project shape

---

## Phase 1: Strip and Build

### 1a. Create migration branch
- [ ] `git checkout -b swiftui-migration`

### 1b. Bulk directory removals
- [x] Delete `qt/aqt/` (PyQt GUI)
- [x] Delete `ts/` (Svelte/TypeScript frontend)
- [x] Delete `pylib/` (Python library + PyO3 bridge)
- [x] Delete `python/` (Python utilities)
- [x] Delete `tools/` except `tools/minilints`
- [x] Delete `.github/` (CI workflows)
- [x] Delete `.buildkite/` (CI config)
- [x] Delete `.idea.dist/` (IntelliJ config)
- [x] Delete `.vscode.dist/` (VS Code config)
- [x] Delete `.cursor/` (Cursor IDE config)

### 1c. Root file removals
- [x] Delete `package.json`
- [x] Delete `yarn.lock`, `.yarnrc.yml`, `yarn`, `yarn.bat`
- [x] Delete `pyproject.toml`, `uv.lock`, `.python-version`
- [x] Delete `.mypy.ini`, `.ruff.toml`
- [x] Delete `.eslintrc.cjs`, `.prettierrc`, `.dprint.json`
- [x] Delete `.readthedocs.yaml`, `.dockerignore`
- [x] Delete `run.bat`

### 1d. Partial directory cleanups
- [x] Remove `qt/launcher/src/platform/windows.rs`
- [x] Remove `qt/launcher/src/platform/unix.rs`
- [x] Remove `qt/launcher/src/bin/` (Windows binaries)
- [x] Remove `qt/icons/`, `qt/release/`, `qt/tests/`, `qt/tools/`
- [x] Remove `docs/windows.md`, `docs/linux.md`

### 1e. Codegen cleanup
- [x] Delete `rslib/proto/python.rs`
- [x] Delete `rslib/proto/typescript.rs`
- [x] Edit `rslib/proto/build.rs` -- remove python/typescript calls and mod declarations
- [x] Delete `rslib/i18n/python.rs` (if exists)
- [x] Delete `rslib/i18n/typescript.rs` (if exists)
- [x] Edit `rslib/i18n/build.rs` -- remove python/typescript calls (if applicable)

### 1f. Windows-specific Rust removal
- [x] Delete `rslib/src/card_rendering/tts/windows.rs`
- [x] Delete `rslib/src/error/windows.rs`
- [x] Edit `rslib/src/card_rendering/tts/mod.rs` -- remove `#[cfg(windows)]` branch
- [x] Edit `rslib/src/error/mod.rs` -- remove `WindowsError` variant
- [x] Edit `rslib/src/backend/error.rs` -- remove Windows error handling

### 1g. Build system migration
- [x] Install protoc: `brew install protobuf`
- [x] Edit `.cargo/config.toml` -- remove DESCRIPTORS_BIN, PROTOC, STRINGS_*, PYO3_NO_PYTHON, Windows rustflags
- [x] Edit `rslib/proto/rust.rs` -- remove `set_protoc_path()` function
- [x] Edit `rslib/build.rs` -- replace `out/buildhash` with `git rev-parse --short HEAD`

### 1h. Workspace cleanup
- [x] Edit root `Cargo.toml` -- remove non-Rust workspace members (build/*, pylib/rsbridge, tools/minilints)
- [x] Edit root `Cargo.toml` -- remove Windows deps (winapi, windows, widestring, embed-resource, junction, libc-stdhandle)
- [x] Edit root `Cargo.toml` -- remove `pyo3` dependency
- [x] Edit `qt/launcher/Cargo.toml` -- remove Windows/Linux platform configs (qt/ directory removed)

### 1i. Validation
- [x] Run `cargo check --workspace`
- [ ] Run `cargo test --workspace`
- [x] Grep for stale references: `grep -r "pylib\|aqt\|rsbridge\|pyo3" rslib/ --include="*.rs"` (no matches found)
- [ ] Commit: "strip non-Rust code for macOS-only SwiftUI build"

---

## Phase 2: Swift FFI Bridge

### 2a. Rust bridge crate
- [x] Create `bridge/Cargo.toml` (crate-type = ["staticlib"])
- [x] Implement `ByteBuffer` struct for FFI byte transfer
- [x] Implement `anki_init()` -- create Backend from protobuf bytes
- [x] Implement `anki_command()` -- RPC dispatch
- [x] Implement `anki_free()` -- drop Backend
- [x] Implement `anki_free_buffer()` -- free returned bytes
- [x] Add `bridge` to workspace members
- [x] Verify `cargo build -p anki_bridge` produces `libanki_bridge.a`

### 2b. Swift protobuf generation
- [x] Install swift-protobuf: `brew install swift-protobuf`
- [x] Generate Swift types: `protoc --swift_out=AnkiApp/Proto/ proto/anki/*.proto`
- [x] Verify generated types compile

### 2c. Xcode project setup
- [x] Create `AnkiApp/` Xcode project (SwiftUI, macOS 13+)
- [x] Add `AnkiBridge.h` bridging header
- [x] Link `libanki_bridge.a` in Build Settings
- [x] Set Library Search Paths to `target/release/`
- [x] Add Run Script build phase for `cargo build --release -p anki_bridge`

### 2d. Swift bridge layer
- [x] Implement `AnkiBackend.swift` -- init, command, deinit wrappers
- [x] Implement `AnkiService.swift` -- async actor with typed methods
- [x] Test: open collection file from SwiftUI

---

## Phase 3: Core SwiftUI App

### 3a. Navigation and data flow
- [x] Design app navigation structure (sidebar + detail)
- [x] Create `CollectionManager` for collection lifecycle (AppState)
- [x] Implement collection open/close flow

### 3b. Deck browser
- [x] Deck list view with card counts
- [x] Due/new/review count display
- [x] Deck selection to start review

### 3c. Reviewer
- [x] Card front display (HTML rendering via WKWebView)
- [x] Show answer / flip card
- [x] Answer buttons (Again / Hard / Good / Easy)
- [x] Progress bar (remaining cards)
- [x] Congratulations screen (deck complete)

### 3d. Note editor
- [x] Field-per-notetype layout
- [x] Rich text editing (bold, italic, cloze) (basic formatting; lists/links pending)
- [x] Tag editor
- [x] Deck selector
- [x] Note type selector
- [x] Save / update note

### 3e. Search
- [x] Search bar with Anki query syntax
- [x] Results list (note preview, deck, tags)
- [x] Click to edit note
- [ ] Browser-style column view

### 3f. Supporting screens
- [x] Deck options / scheduling settings
- [x] Statistics (review history, forecast charts)
- [x] Import .apkg files
- [x] Export .apkg files
- [x] AnkiWeb sync with progress
- [x] Preferences (collection path, language, appearance)

---

## Phase 4: Atlas Integration

### 4a. Copy and compile
- [x] Copy atlas crates into `atlas/` subdirectory
- [x] Add all atlas crates to workspace `Cargo.toml`
- [x] Upgrade workspace to Rust edition 2024
- [x] Update `rust-toolchain.toml` to 1.92+
- [x] Resolve `rusqlite` version conflict (upgrade atlas to 0.36)
- [x] Resolve `reqwest` version conflict
- [x] Resolve `strum` version conflict (upgrade anki to 0.28)
- [x] Resolve `phf` version conflict
- [x] Run `cargo check --workspace` -- fix remaining compile errors

### 4b. Replace anki-reader
- [x] Define `AnkiDataSource` trait in `atlas/common/`
- [x] Implement `CollectionSource` adapter using `anki::backend::Backend` (SqliteAnkiDataSource)
- [x] Add `From` impls: `anki_proto` types -> atlas types
- [x] Update `anki-sync` to use `AnkiDataSource` trait
- [x] Update `surface-runtime` to wire `CollectionSource`
- [x] Remove `anki-reader` crate from workspace

### 4c. Desktop infrastructure
- [x] Implement `InMemoryJobManager` (replace Redis)
- [x] Feature-gate Redis: `#[cfg(feature = "redis")]`
- [x] Configure Qdrant embedded mode (replaced with PostgreSQL + pgvector)
- [x] Evaluate PostgreSQL strategy (embedded-postgres vs SQLite)
- [x] Implement chosen PostgreSQL strategy (PostgreSQL with pgvector)

### 4d. Validation
- [x] Run `cargo check --workspace`
- [x] Run `cargo test --workspace --exclude database --exclude anki-sync`
- [x] Integration test: AnkiDataSource reads from real collection
- [x] Commit: "integrate anki-atlas crates into workspace"

---

## Phase 5: Atlas Features in SwiftUI

### 5a. Search enhancement
- [ ] Wire hybrid search (FTS + semantic) into search screen
- [ ] Add search mode toggle (hybrid / semantic / FTS)
- [ ] Display relevance scores

### 5b. Analytics screens
- [ ] Topic taxonomy tree view
- [ ] Topic coverage metrics display
- [ ] Gap detection view (topics needing more cards)
- [ ] Weak notes list (low-quality cards)
- [ ] Duplicate detection view

### 5c. AI features
- [ ] LLM card generation from text/URL
- [ ] Card validation and quality scoring
- [ ] Card improvement suggestions
- [ ] Obsidian vault browser and sync

### 5d. Knowledge graph
- [ ] Concept relationship visualization
- [ ] Topic edge browser

### 5e. External tools
- [ ] Wire `bins/mcp/` binary for Claude Code
- [ ] Wire `bins/cli/` binary for automation
- [ ] Test MCP tools with Claude Code

---

## Phase 6: Polish and Distribution

- [ ] App icon design
- [ ] Visual polish (colors, typography, animations)
- [ ] macOS app packaging (.dmg)
- [ ] Code signing and notarization
- [ ] AGPL-3.0 compliance (license display, source offer)
- [ ] Evaluate Mac App Store distribution
- [ ] Performance profiling and optimization
- [ ] Crash reporting (opt-in)
- [ ] User documentation / help screens
- [ ] README update for the new project
