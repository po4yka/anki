# Convention Audit

## Overview

Code quality rules enforced across the codebase. Use this skill to audit
code for convention violations.

## Rust Conventions

### rslib/ (core library)

- **Error handling**: Use `AnkiError`/`Result` from `error/mod.rs` with `snafu`
- **No `unwrap()`**: Forbidden in library code (OK in tests and build scripts)
- **No `expect()`**: Forbidden in library code
- **Tracing**: `#[instrument]` on public async functions

### atlas/ (AI crates)

- **Error handling**: Use `thiserror` for typed errors
- **Thread safety**: All types must be `Send + Sync`
- **Shared state**: `Arc<T>`, never `Rc<T>`
- **No `unwrap()`**: Forbidden in library crates
- **Tracing**: `#[instrument]` on public async functions
- **Mocking**: `#[cfg_attr(test, mockall::automock)]` on traits

### bins/ (CLI, MCP server)

- **Error handling**: Use `anyhow` with `.context()`
- **`unwrap()`**: Acceptable in build scripts

### General Rust

- Dependencies in workspace root `Cargo.toml` with `dep.workspace = true`
- Newtype pattern for domain IDs: `pub struct NoteId(pub i64)`

## Swift Conventions

- **`@Observable`**: Required. Never use `ObservableObject`
- **No Combine**: Use `AsyncSequence` / `async-await` instead
- **No XCTest**: Use Swift Testing (`@Test`, `#expect`)
- **No force-unwrap** (`!`): Use `guard let` or `if let`
- **One type per file**
- **Views under 100 lines**: Extract subviews when exceeded
- **SF Symbols**: For all icons
- **Semantic colors**: System colors, not hardcoded values

## Audit Checklist

1. `grep -rn "unwrap()" rslib/src/ --include="*.rs"` -- exclude tests
2. `grep -rn "ObservableObject" AnkiApp/ --include="*.swift"`
3. `grep -rn "import Combine" AnkiApp/ --include="*.swift"`
4. `grep -rn "import XCTest" AnkiApp/ --include="*.swift"`
5. Verify `ServiceConstants.swift` indices match proto method order
6. Check `#[instrument]` on public async functions in `atlas/`

## When to Use

- Before code review
- After adding new crates or Swift files
- Periodic codebase health checks
