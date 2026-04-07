# Contributing to Anki

## Prerequisites

```bash
brew install protobuf swift-protobuf
cargo build --workspace
```

For SwiftUI development, open `AnkiApp/AnkiApp.xcodeproj` in Xcode.

Optional: `brew install swiftlint` for Swift linting.

## Architecture

```
SwiftUI App (AnkiApp/) -> C-ABI FFI (bridge/) -> Rust Backend (rslib/) + Atlas Services (atlas/)
```

- **rslib/**: Core Anki engine -- collection, scheduler, sync, search, storage (SQLite)
- **atlas/**: Analytics, hybrid search, embeddings, LLM card generation
- **bridge/**: C-ABI staticlib exposing protobuf-serialized RPCs to Swift
- **AnkiApp/**: Native macOS SwiftUI interface
- **proto/anki/**: 22 protobuf files defining the cross-language API
- **bins/**: CLI and MCP server

## Rust Conventions

### Error handling

| Crate | Strategy |
|-------|----------|
| `rslib/` | `AnkiError` / `Result` with `snafu` |
| `atlas/` library crates | `thiserror` for typed errors |
| `bins/` | `anyhow` with `.context()` |
| Build scripts, tests | `unwrap()` / `expect()` are fine |

### Rules

- No `unwrap()` or `expect()` in library crates (`rslib/`, `atlas/`)
- All types in `atlas/` must be `Send + Sync`
- Use `Arc<T>` for shared state, never `Rc<T>`
- Newtype pattern for domain IDs: `pub struct NoteId(pub i64)`
- `#[instrument]` on public async functions for tracing
- Trait-based dependency injection at external boundaries
- `#[cfg_attr(test, mockall::automock)]` on traits
- Add workspace deps to root `Cargo.toml`, use `dep.workspace = true` in crates

## Swift Conventions

- Use `@Observable` (not `ObservableObject`)
- Use `async/await` (not Combine)
- Use Swift Testing framework (not XCTest)
- No force-unwraps (`as!`, `!`) in production code

## Adding a New Feature

The typical workflow for a cross-layer feature:

1. **Proto**: Define messages and RPC in `proto/anki/*.proto`
2. **Rust service**: Implement the service method in `rslib/` or `atlas/`
3. **Bridge**: Expose via C-ABI in `bridge/`
4. **Proto regen**: `protoc --swift_out=AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto`
5. **ViewModel**: Create Swift ViewModel calling the bridge
6. **View**: Build SwiftUI view consuming the ViewModel

## Pre-commit Hooks

Set up the project hooks:

```bash
git config core.hooksPath .githooks
```

This runs `cargo fmt` and `cargo clippy` checks before each commit. Bypass with `SKIP_HOOKS=1 git commit`.

See `.githooks/README.md` for details.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scheduler): add FSRS parameter optimization
fix(bridge): handle null proto fields in card rendering
refactor(atlas/search): extract embedding pipeline
docs: update FFI bridge examples
test(rslib): add sync conflict resolution tests
```

## Testing

- **Rust**: `cargo test --workspace`
- **Single crate**: `cargo test -p anki` or `cargo test -p search`
- **Swift**: Run tests from Xcode or `xcodebuild test`

All PRs should include tests for new functionality. Rust library crates should have unit tests; integration tests go in `tests/` directories.

## Code Audit

Run the audit script to check for common issues:

```bash
./scripts/audit.sh
```

This checks Rust formatting/linting, unwrap usage, Swift anti-patterns, and proto/bridge consistency.
