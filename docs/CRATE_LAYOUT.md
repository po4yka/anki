# Crate Layout

## Architecture Overview

```
SwiftUI App -> C-ABI FFI (bridge/ + atlas_bridge/) -> Rust Backend (rslib/) + Atlas Services (atlas/)
```

The workspace is organized into 32 crates across five groups: the Anki core engine (rslib), FFI bridges, Atlas AI/analytics services, executables, and translation infrastructure.

## Layer Diagram

```
┌─────────────────────────────────────────┐
│  SwiftUI (AnkiApp/)                     │  macOS native UI
├─────────────────────────────────────────┤
│  FFI Bridges                            │
│  • bridge/ (protobuf-based core RPC)    │  C-ABI staticlibs
│  • atlas_bridge/ (JSON-based analytics) │  exported to Swift
│  • ffi_common/ (ByteBuffer, error mgmt) │
├───────────────────┬─────────────────────┤
│  rslib/           │  atlas/             │
│  • anki (core)    │  • analytics        │  Rust backend services
│  • i18n           │  • search           │  with SQLite/PostgreSQL
│  • proto          │  • generator        │
│  • sync           │  • rag              │
│  • io, process    │  • 14 other crates  │
└───────────────────┴─────────────────────┘
```

## Crate Directory

### rslib -- Anki Core Engine

| Crate | Package Name | Purpose |
|-------|-------------|---------|
| `rslib/` | `anki` | Core engine: collection, scheduler, search, sync, storage (SQLite), note/card manipulation, deck management, template rendering |
| `rslib/i18n` | `anki_i18n` | Type-safe i18n API generated from Fluent translation files; locale loading and formatting |
| `rslib/io` | `anki_io` | File system operations with better error context; directory creation, file reading/writing, temporary files |
| `rslib/process` | `anki_process` | Process spawning with error handling; used for external utilities |
| `rslib/proto` | `anki_proto` | Protobuf message definitions and generated Rust code; 24 .proto files defining the core API |
| `rslib/proto_gen` | `anki_proto_gen` | Code generation from protobuf; builds the Rust proto bindings |
| `rslib/sync` | (inline in anki) | Collection synchronization with AnkiWeb; conflict resolution, sync protocol |

### FFI Bridges -- Swift Interop

| Crate | Package Name | Purpose |
|-------|-------------|---------|
| `bridge/` | `anki_bridge` | C-ABI bridge exporting protobuf-based RPC interface to Swift; `anki_init()`, `anki_command()`, `anki_free()` |
| `atlas_bridge/` | `atlas_bridge` | C-ABI bridge for atlas services (analytics, search, generation); JSON-based responses |
| `ffi_common/` | `ffi_common` | Shared FFI utilities: `ByteBuffer` for owned data transfer, panic catching, error handling |

### Atlas -- AI and Analytics Services (19 crates)

| Crate | Purpose |
|-------|---------|
| `atlas/common` | Configuration, logging, error types, and shared utilities; loads env vars prefixed `ANKIATLAS_` |
| `atlas/database` | PostgreSQL schema, migrations, connection pooling, and low-level query builders |
| `atlas/analytics` | Card and deck analytics; duplicate detection, labeling statistics, taxonomy analysis |
| `atlas/search` | Hybrid search (semantic + keyword); embedding generation and reranking |
| `atlas/generator` | AI-powered card generation from study materials; prompt engineering, LLM integration |
| `atlas/indexer` | Incremental indexing of notes and cards; embedding computation and storage |
| `atlas/ingest` | Content ingestion pipeline; Markdown, Obsidian, and web content processing |
| `atlas/rag` | Retrieval-augmented generation; context assembly for LLM prompts |
| `atlas/jobs` | Async job queue and worker management; PostgreSQL-backed task scheduling |
| `atlas/llm` | LLM provider integration; OpenAI, Google, local model abstractions |
| `atlas/card` | Card-related domain logic; note-to-card conversion, template rendering |
| `atlas/cardloop` | Spaced repetition scheduling integration; FSRS algorithm application |
| `atlas/knowledge-graph` | Knowledge graph construction from card relationships and tags |
| `atlas/rag` | Retrieval-augmented generation for contextual AI responses |
| `atlas/taxonomy` | Note classification and hierarchical organization; topic taxonomy |
| `atlas/validation` | Schema and content validation; field constraints, format checking |
| `atlas/obsidian` | Obsidian vault integration; vault parsing and content extraction |
| `atlas/surface-contracts` | Domain types and API contracts shared across atlas services |
| `atlas/surface-runtime` | HTTP server runtime for atlas API; Axum-based request handling |

### Executables

| Crate | Package Name | Purpose |
|-------|-------------|---------|
| `bins/cli/` | `anki_cli` | Terminal CLI for batch operations; collection management, card import, sync |
| `bins/mcp/` | `anki_mcp` | Model Context Protocol server for Claude Code integration; read-only codebase access |

### Other

| Crate | Package Name | Purpose |
|-------|-------------|---------|
| `ftl/` | (none) | Fluent translation files (i18n strings) for the Anki UI |

## Dependency Graph (Simplified)

```
SwiftUI (AnkiApp/)
  ├── bridge/ (C-ABI)
  │   ├── anki (rslib/)
  │   └── ffi_common/
  │
  └── atlas_bridge/ (C-ABI JSON)
      ├── atlas/surface-runtime (HTTP server)
      │   ├── atlas/surface-contracts
      │   ├── atlas/analytics
      │   ├── atlas/search
      │   ├── atlas/generator
      │   ├── atlas/jobs
      │   └── [other atlas crates]
      │
      └── ffi_common/

anki (rslib/)
  ├── anki_i18n
  ├── anki_io
  ├── anki_proto
  ├── rusqlite (SQLite)
  ├── serde (serialization)
  └── [external crates: tokio, regex, nom, etc.]

atlas/* (library crates)
  ├── atlas/common (config, logging)
  ├── atlas/database (PostgreSQL/SQLx)
  ├── atlas/surface-contracts (domain types)
  ├── [internal dependencies vary by crate]
  └── [external: tokio, axum, sqlx, fastembed, etc.]

anki_cli (bins/cli/)
  ├── anki (rslib/)
  ├── atlas/* (selective)
  └── clap (CLI parsing)

anki_mcp (bins/mcp/)
  ├── rmcp (Model Context Protocol)
  └── file system (read-only)
```

## Adding New Crates

### 1. Create the Crate

```bash
cargo new --lib crates/my_feature
# OR for a binary
cargo new --bin bins/my_tool
```

### 2. Register in Workspace

Edit `/Cargo.toml` and add to `[workspace] members`:

```toml
[workspace]
members = [
  # ... existing crates ...
  "crates/my_feature",  # or "bins/my_tool"
]
```

### 3. Set Up Cargo.toml

Use workspace dependencies where possible:

```toml
[package]
name = "my_feature"
version.workspace = true
authors.workspace = true
edition.workspace = true
license.workspace = true
publish = false
rust-version.workspace = true

[dependencies]
# Workspace crates
anki.workspace = true
ffi_common.workspace = true

# Workspace dependencies (preferred)
tokio.workspace = true
serde.workspace = true
thiserror.workspace = true

# External crates (if needed, use latest compatible version)
# and add to [workspace.dependencies] in root Cargo.toml
```

### 4. Follow Conventions

- **Library crates (atlas/*)**: Use `thiserror` for typed errors, `#[instrument]` on public async functions, `Arc<T>` for shared state (never `Rc<T>`), newtype pattern for domain IDs
- **Binary crates (bins/*)**: Use `anyhow` with context, `clap` for CLI parsing
- **Build scripts**: `unwrap()` and `expect()` are OK; use `anyhow` for errors
- **Tests**: Can use `unwrap()` freely

### 5. Add to CI/CD

Update `.github/workflows/` to build and test the new crate:

```bash
cargo check -p my_feature
cargo test -p my_feature
```

## Workspace Conventions

### Dependency Management

- Prefer adding to `[workspace.dependencies]` in root `Cargo.toml`
- Use `dep.workspace = true` in individual crate manifests
- Pinned versions only when necessary (e.g., unicase for SQLite index stability)

### Build Profiles

```toml
[profile.dev.package."*"]
opt-level = 1          # Mild optimizations for dependencies
debug = 0              # Faster incremental builds

[profile.release-lto]
inherits = "release"
lto = true             # Full link-time optimization
```

### Lints

Workspace lints apply to all crates:

```toml
[workspace.lints.rust]
unsafe_code = "warn"

[workspace.lints.clippy]
unwrap_used = "warn"
expect_used = "warn"
panic = "warn"
```

Per-crate overrides allowed in individual `Cargo.toml` (e.g., `ffi_common/` allows `unsafe_code`).

## Proto Regeneration

When modifying `.proto` files in `proto/anki/`:

```bash
# Automatically regenerated on build
cargo build -p anki_bridge

# Manual Swift type regeneration
protoc --swift_out=AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto
```

## See Also

- `CONTRIBUTING.md` -- Contributor guidelines and development workflow
- `docs/migration/` -- Full migration plan and architecture rationale
- `ROADMAP.md` -- Project phases and release planning
- Custom skills in `.claude/skills/` for specialized workflows
