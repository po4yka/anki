# Claude Code Configuration

## Project Overview

Anki SwiftUI is a macOS-only spaced repetition flashcard application built
on Anki's Rust core, enhanced with anki-atlas analytics and AI capabilities,
and presented through a native SwiftUI interface.

This is a migration from the original multi-platform Anki (Python/Qt/Svelte)
to a Rust + Swift architecture. See `docs/migration/` for the full migration
plan, `ROADMAP.md` for phases, and `TODO.md` for the task checklist.

### Architecture

```
SwiftUI App -> C-ABI FFI (bridge/) -> Rust Backend (rslib/) + Atlas Services (atlas/)
```

### Main components

- Core Rust layer: `rslib/` -- collection, scheduler, sync, search, storage (SQLite)
- Protobuf API: `proto/anki/` -- 24 .proto files defining the cross-language interface
- Swift FFI bridge: `bridge/` -- C-ABI staticlib with protobuf serialization
- Atlas crates: `atlas/` -- hybrid search, embeddings, LLM card generation, analytics
- MCP server: `bins/mcp/` -- Claude Code integration via Model Context Protocol
- CLI: `bins/cli/` -- terminal automation
- SwiftUI app: `AnkiApp/` -- native macOS interface

## Building

### Rust
```bash
cargo check --workspace          # type check everything
cargo build --workspace          # build all crates
cargo test --workspace           # run all tests
cargo build -p anki_bridge       # build Swift FFI bridge only
```

### Prerequisites
```bash
brew install protobuf            # required for proto compilation
brew install swift-protobuf      # required for Swift proto types
```

### Proto regeneration
Proto changes require rebuilding both Rust (automatic via build.rs) and
Swift types:
```bash
protoc --swift_out=AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto
```

## Quick iteration

- Rust core: `cargo check -p anki`
- Bridge: `cargo check -p anki_bridge`
- Atlas crates: `cargo check -p search -p indexer -p analytics`
- Full workspace: `cargo check --workspace`
- SwiftUI: Open `AnkiApp/AnkiApp.xcodeproj` in Xcode

## Translations

`ftl/core/` contains Fluent translation files. `rslib/i18n` auto-generates
a type-safe Rust API. When adding new strings, add to `ftl/core/` and match
the existing style.

## Protobuf and IPC

The 24 .proto files in `proto/anki/` define the Rust backend's API. The
`bridge/` crate exposes this API to Swift via C-ABI functions:
- `anki_init(bytes, len)` -- create Backend from protobuf BackendInit
- `anki_command(backend, service, method, bytes, len)` -- RPC dispatch
- `anki_free(backend)` -- release Backend

Swift uses `swift-protobuf` generated types to serialize/deserialize
requests and responses.

## Fixing errors

Run `cargo check --workspace` regularly during development. For proto-related
errors, do a `cargo clean` first then rebuild. For Swift build errors, ensure
the Rust staticlib is built before Xcode compiles.

## Rust dependencies

Prefer adding to the root workspace `Cargo.toml` and using
`dep.workspace = true` in individual crate `Cargo.toml` files.

## Rust utilities

`rslib/{process,io}` contain helpers for file and process operations with
better error context. Use them when possible.

## Rust error handling

- In `rslib/`: use `error/mod.rs` AnkiError/Result and snafu
- In `atlas/` library crates: use `thiserror` for typed errors
- In `bins/`: use `anyhow` with context
- Unwrapping in build scripts and tests is fine

## Atlas crates conventions

- All types must be `Send + Sync`
- Trait-based DI at external boundaries
- `#[cfg_attr(test, mockall::automock)]` on traits
- Newtype pattern for domain IDs: `pub struct NoteId(pub i64)`
- `#[instrument]` on public async functions for tracing
- `Arc<T>` for shared state, never `Rc<T>`
- No `unwrap()` or `expect()` in library crates

## Migration docs

- `docs/migration/architecture.md` -- target system architecture
- `docs/migration/stripping-guide.md` -- what to remove/modify
- `docs/migration/build-migration.md` -- cargo build migration
- `docs/migration/swift-ffi.md` -- Swift FFI bridge design
- `docs/migration/atlas-integration.md` -- atlas crate integration

## Individual preferences

See @.claude/user.md
