# Anki SwiftUI for macOS

A native spaced repetition flashcard application for macOS, built on Anki's proven scheduling engine with AI-powered analytics and hybrid search.

<!-- TODO: Add screenshot -->

## Features

### Core Spaced Repetition
- **FSRS algorithm** for optimal review scheduling
- **Deck browser** with hierarchical organization
- **Card reviewer** with WKWebView rendering
- **Note editor** with rich text and LaTeX support
- **Statistics** using Swift Charts for progress visualization
- **AnkiWeb sync** with conflict resolution

### Atlas AI Capabilities
- **Hybrid search**: Semantic + full-text search with RRF ranking
- **Topic analytics**: Coverage reports and gap detection
- **Duplicate finder**: Identify similar cards across decks
- **Card generation**: AI-powered card creation from source text
- **Obsidian sync**: Bidirectional vault synchronization
- **Quality validation**: Duplicate detection and taxonomy normalization

### Developer Tools
- **MCP server** for Claude Code integration (bins/mcp/)
- **CLI automation** for scripting and batch operations (bins/cli/)

## Architecture

```
SwiftUI App -> C-ABI FFI -> Rust Backend + Atlas Services
    ↓              ↓                ↓
 (UI, views)  (bridge/)    (rslib + atlas/)
                                   ↓
                    (SQLite + PostgreSQL + pgvector)
```

### Stack Overview

| Layer | Component | Technology |
|-------|-----------|-----------|
| Frontend | User interface | SwiftUI (macOS 13+) |
| Bridge | C-ABI FFI | Protocol Buffers + staticlib |
| Core | Scheduling & sync | Anki's Rust backend (rslib) |
| Analytics | AI services | Atlas crates (search, generation, analytics) |
| Storage | Persistence | SQLite (local), PostgreSQL + pgvector (vector embeddings) |
| Integration | Claude Code | MCP server binary |

## Prerequisites

- **macOS 13.0** (Ventura) or later
- **Xcode 15+**
- **Rust 1.88+** (via [rustup](https://rustup.rs/))
- **Protocol Buffers**: `brew install protobuf`
- **Swift Protobuf**: `brew install swift-protobuf`
- **PostgreSQL 15+** (for vector embeddings): `brew install postgresql@15`
- **Docker** (optional, for testcontainers in integration tests)

## Build Instructions

### 1. Clone and set up dependencies

```bash
git clone https://github.com/ankitects/anki.git
cd anki
brew install protobuf swift-protobuf
```

### 2. Build the Rust backend

```bash
# Check everything compiles
cargo check --workspace

# Build the Swift FFI bridge (release mode for app)
cargo build --release -p anki_bridge
```

### 3. Build the macOS app

```bash
# Open the Xcode project
open AnkiApp/AnkiApp/AnkiApp.xcodeproj
```

In Xcode:
- Select the **AnkiApp** scheme
- Press **Cmd+B** to build
- Press **Cmd+R** to run

The build phase script will automatically:
1. Compile the Rust staticlib (`libbridge.a`)
2. Generate Swift protobuf types from `.proto` files
3. Link the bridge into the app bundle

### 4. (Optional) Build CLI and MCP tools

```bash
# CLI automation tool
cargo build --release -p cli

# MCP server for Claude Code
cargo build --release -p mcp
```

## Development Setup

### Quick iteration (Rust core)

```bash
# Type-check all crates
cargo check --workspace

# Check specific crate
cargo check -p anki
cargo check -p search
cargo check -p analytics

# Run tests
cargo test --workspace
```

### Proto regeneration

If you modify `.proto` files in `proto/anki/`:

```bash
# Regenerate both Rust and Swift types
protoc --swift_out=AnkiApp/Proto/ \
       --proto_path=proto/ \
       proto/anki/*.proto

# Rust types regenerate automatically on next cargo build
cargo build --release -p anki_bridge
```

### Translations

Add new strings to `ftl/core/` using Fluent syntax. `rslib/i18n` auto-generates a type-safe Rust API. Match existing style and placeholder names.

## Project Structure

```
anki/
├── rslib/                      # Anki Rust core (68K+ lines)
│   ├── src/                    # Collection, scheduler, sync, storage
│   ├── sync/                   # AnkiWeb sync client
│   ├── i18n/                   # Internationalization (Fluent)
│   ├── io/, process/           # File and process utilities
│   └── proto/                  # Protobuf code generation
│
├── atlas/                      # AI/analytics crates
│   ├── search/                 # Hybrid FTS + semantic search
│   ├── indexer/                # Embeddings + PostgreSQL/pgvector
│   ├── database/               # PostgreSQL connection pooling
│   ├── analytics/              # Coverage, gaps, duplicates
│   ├── generator/              # LLM card generation
│   ├── validation/             # Quality pipeline
│   ├── obsidian/               # Vault sync
│   ├── cardloop/               # FSRS feedback loop
│   ├── llm/                    # LLM provider abstraction
│   └── surface-runtime/        # Service facade
│
├── bridge/                     # C-ABI FFI staticlib for Swift
│
├── AnkiApp/                    # Xcode project
│   ├── Sources/
│   │   ├── Bridge/             # Swift FFI wrappers
│   │   ├── Services/           # AnkiService, async coordination
│   │   ├── Views/              # SwiftUI views
│   │   └── Models/             # View models (@Observable)
│   ├── Proto/                  # Generated Swift protobuf types
│   ├── AnkiAppTests/           # Unit tests
│   └── AnkiAppUITests/         # UI/integration tests
│
├── proto/anki/                 # 24 .proto service definitions
│   └── *.proto                 # Shared API spec (source of truth)
│
├── bins/
│   ├── mcp/                    # MCP server for Claude Code
│   └── cli/                    # CLI for automation/scripting
│
├── ftl/core/                   # Fluent translation files
│
├── docs/
│   ├── TESTING.md              # Testing strategy & patterns
│   └── migration/              # Migration documentation
│
└── Cargo.toml                  # Unified workspace manifest
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Add note | Cmd+N |
| Open deck browser | Cmd+1 |
| Search cards | Cmd+F |
| Sync collection | Cmd+S |
| Settings | Cmd+, |
| Fullscreen reviewer | Cmd+Enter |
| Answer card (Space/1-4) | `1` / `2` / `3` / `4` |
| Undo | Cmd+Z |
| Quit | Cmd+Q |

## Common Tasks

### Running tests

```bash
# All tests
cargo test --workspace

# Specific crate
cargo test -p search

# With output
cargo test -- --nocapture
```

### Checking for errors

```bash
# Full workspace diagnostics
cargo check --workspace

# If proto issues, clean and rebuild
cargo clean
cargo build --release -p anki_bridge
```

### Adding a new dependency

Edit `Cargo.toml` in the workspace root under `[workspace.dependencies]`, then reference it with `dep.workspace = true` in individual crate `Cargo.toml` files.

## Architecture Notes

### FFI Contract

The bridge exposes three C-ABI functions:
- `anki_init(bytes, len)` - Initialize backend from protobuf BackendInit
- `anki_command(backend, service, method, bytes, len)` - RPC dispatch
- `anki_free(backend)` - Release backend resources

Swift serializes requests and deserializes responses using generated protobuf types.

### Concurrency

- `AnkiService` is a Swift actor that serializes all backend calls
- View models are `@Observable @MainActor` classes
- Backend pointer is thread-safe on Rust side (Arc<Mutex<...>>)

### Error Handling

- **rslib**: Uses `error/mod.rs` with snafu for typed errors
- **atlas crates**: Use `thiserror` for trait-based errors
- **bins**: Use `anyhow` with context
- **Tests/build scripts**: Unwrapping is acceptable

### Atlas Conventions

- All public types are `Send + Sync`
- Trait-based dependency injection at boundaries
- `#[instrument]` on async functions for tracing
- Domain IDs as newtypes: `pub struct NoteId(pub i64)`
- `Arc<T>` for shared state (never `Rc<T>`)
- No `unwrap()` in library crates

## Troubleshooting

**Proto compilation errors**: Run `cargo clean` first, then `cargo build --release -p anki_bridge`

**Xcode build fails**: Ensure the Rust staticlib is built before compiling in Xcode. Run `cargo build --release -p anki_bridge` manually if needed.

**Bridge header not found**: Run the build phase script manually: `cd AnkiApp && ./build_bridge.sh` (if present) or rebuild the bridge crate.

**Swift type mismatches**: Regenerate proto types: `protoc --swift_out=AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto`

## Contributing

See [CONTRIBUTING.md](./docs/contributing.md) and [Development Guide](./docs/development.md).

For migration details, see [Migration Documentation](./docs/migration/), including:
- [Architecture Design](./docs/migration/architecture.md)
- [Swift FFI Bridge](./docs/migration/swift-ffi.md)
- [Build Migration](./docs/migration/build-migration.md)

## License

**AGPL-3.0-or-later**

Anki's source code is licensed under the GNU Affero General Public License v3. See [LICENSE](./LICENSE) for details.

The combined work (Anki + anki-atlas) is AGPL-3.0. For macOS App Store distribution, evaluate AGPL compatibility with your legal team, as AGPL source-offer requirements may conflict with standard App Store terms.

## Credits

- **Ankitects Pty Ltd** - Anki's original design and maintenance
- **anki-atlas project** - AI analytics and hybrid search
- **FSRS algorithm** - Spaced repetition optimization
- All contributors in [CONTRIBUTORS](./CONTRIBUTORS)
