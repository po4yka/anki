# AGENTS.md

## Architecture Layers

```
Layer 4: SwiftUI App       (AnkiApp/)        -- Views, ViewModels, resources
Layer 3: C-ABI Bridge      (bridge/)          -- FFI staticlib, proto serialization
Layer 2: Atlas Services     (atlas/)           -- Search, embeddings, LLM, analytics
Layer 1: Rust Core          (rslib/)           -- Collection, scheduler, sync, storage
Layer 0: Protobuf API       (proto/anki/)      -- Cross-language interface definitions
```

### Dependency Rules

- **Down only**: Each layer may depend on layers below it, never above.
- **atlas/ does not import rslib/ directly** -- use trait boundaries for shared abstractions.
- **bridge/ depends on rslib/ and atlas/** -- it is the integration point.
- **AnkiApp/ depends only on bridge/** via C-ABI calls and protobuf types.
- **proto/ has no code dependencies** -- it is the source of truth for the API contract.

## Quality Gates

All changes must pass before merge:

1. `cargo fmt --all -- --check` -- consistent formatting
2. `cargo clippy --workspace -- -D warnings` -- no lint warnings
3. `cargo test --workspace` -- all tests green
4. No `unwrap()` / `expect()` in library crates (rslib/, atlas/)
5. SwiftLint clean (if modifying AnkiApp/)

Run `./scripts/audit.sh` for a comprehensive check.

## Agent Catalog

Custom agents are defined in `.claude/agents/`:

### architect

- **Role**: Code analysis, architectural guidance, debugging root causes
- **Model**: Opus (read-only)
- **Scope**: All layers -- analyzes cross-cutting concerns and dependency violations
- **Output**: File:line references, root cause analysis, trade-off recommendations

### designer

- **Role**: UI/UX design decisions for the SwiftUI layer
- **Scope**: `AnkiApp/Views/`, `AnkiApp/Models/`, SwiftUI patterns
- **Output**: Design recommendations, component structure, accessibility guidance

### executor

- **Role**: Implementation -- writes and modifies code
- **Scope**: All layers, respecting file ownership rules below
- **Output**: Working code changes with tests

## File Ownership Rules

| Path | Primary Owner | Notes |
|------|--------------|-------|
| `proto/anki/*.proto` | architect | API contract changes need architectural review |
| `rslib/` | executor | Core engine -- requires tests |
| `atlas/` | executor | Must maintain `Send + Sync`, trait-based DI |
| `bridge/` | executor | Integration point -- changes here often follow proto changes |
| `AnkiApp/Views/` | designer, executor | Designer advises, executor implements |
| `AnkiApp/Models/` | executor | ViewModels and data models |
| `AnkiApp/Proto/` | executor | Auto-generated -- regenerate, do not hand-edit |
| `ftl/core/` | executor | Translation strings -- match existing style |
| `bins/` | executor | CLI and MCP server |
| `docs/` | any | Documentation is everyone's responsibility |

## Workspace Rules

### atlas/ crates

- All public types: `Send + Sync`
- External boundaries: trait-based dependency injection
- Traits: `#[cfg_attr(test, mockall::automock)]`
- Domain IDs: newtype pattern (`pub struct NoteId(pub i64)`)
- Public async fns: `#[instrument]` for tracing
- Errors: `thiserror` for typed errors
- Shared state: `Arc<T>`, never `Rc<T>`

### rslib/

- Errors: `AnkiError` / `Result` with `snafu`
- Use helpers from `rslib/io` and `rslib/process` for file/process ops
- No `unwrap()` / `expect()` in library code

### bridge/

- Pure C-ABI surface: `anki_init`, `anki_command`, `anki_free`
- All data crosses the boundary as protobuf bytes
- Must not leak Rust types to Swift

### AnkiApp/

- `@Observable` (not `ObservableObject`)
- `async/await` (not Combine)
- Swift Testing (not XCTest)
- No force-unwraps in production code
