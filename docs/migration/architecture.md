# Target Architecture: Anki SwiftUI (macOS)

## 1. Overview

This project strips Anki's open-source spaced-repetition system (SRS) down to its Rust core (`rslib`), integrates anki-atlas (a Rust-native analytics, search, and LLM platform), and builds a native macOS SwiftUI application on top of both. The result is a single self-contained desktop application that combines Anki's battle-tested scheduling and collection management with atlas's hybrid search, coverage analytics, LLM-driven card generation, and Obsidian vault sync.

The key architectural decisions are:

- All business logic stays in Rust. Swift handles only presentation and user interaction.
- Cross-language communication uses Protocol Buffers over a thin C-ABI FFI bridge, matching Anki's existing IPC model.
- External infrastructure (Redis, network Qdrant, external PostgreSQL) is replaced with in-process equivalents suited to a desktop process: tokio channels, embedded Qdrant, and either embedded PostgreSQL or SQLite.
- A standalone MCP server binary allows Claude Code to drive atlas services directly, without touching the GUI.

---

## 2. System Diagram

```
┌─────────────────────────────────────────────────┐
│                  SwiftUI App                     │
│  (Reviewer, Editor, Deck Browser, Search,        │
│   Analytics, Card Generation)                    │
└──────────────────┬──────────────────────────────┘
                   │ Swift Protobuf
                   ▼
┌──────────────────────────────────────────────────┐
│           C-ABI FFI Bridge (bridge/)             │
│  anki_init() | anki_command() | anki_free()      │
└──────────┬───────────────────────┬───────────────┘
           │                       │
           ▼                       ▼
┌──────────────────┐   ┌──────────────────────────┐
│  Anki Backend    │   │    Atlas Services         │
│  (rslib/)        │   │    (atlas/)               │
│                  │   │                            │
│  - Collection    │   │  - search (hybrid FTS+sem) │
│  - Scheduler     │   │  - indexer (embeddings)    │
│  - Sync client   │   │  - analytics (coverage)    │
│  - Storage(SQLite)│  │  - generator (LLM cards)   │
│  - Cards/Notes   │   │  - obsidian (vault sync)   │
│  - Import/Export │   │  - taxonomy, validation     │
│  - Media mgmt    │   │  - knowledge-graph          │
│  - Card rendering│   │  - cardloop (FSRS feedback) │
└──────────────────┘   └──────────┬────────────────┘
                                  │
                       ┌──────────┴──────────┐
                       │                      │
                  ┌────▼────┐          ┌─────▼─────┐
                  │ Qdrant  │          │ PostgreSQL │
                  │(embedded)│         │ (embedded  │
                  │         │          │  or SQLite) │
                  └─────────┘          └───────────┘

Separate processes (not linked into the app):

┌──────────────────────────┐   ┌────────────────────────────┐
│  MCP Server (bins/mcp/)  │   │  CLI Binary (bins/cli/)    │
│  stdio transport         │   │  automation / scripting    │
│  Claude Code integration │   │                            │
│  -> Atlas surface-runtime│   │  -> rslib + atlas services │
└──────────────────────────┘   └────────────────────────────┘
```

---

## 3. Workspace Layout

```
anki-swiftui/
├── Cargo.toml              # Unified Rust workspace
├── proto/anki/             # 24 .proto files (shared API definition)
├── rslib/                  # Anki Rust core (stripped)
│   ├── src/                # Core library (~68K lines)
│   ├── sync/               # Sync client crate
│   ├── i18n/               # Internationalization
│   ├── io/                 # File/process helpers
│   ├── process/            # Process utilities
│   ├── proto/              # Protobuf codegen (Rust only)
│   └── proto_gen/          # Codegen helpers
├── atlas/                  # anki-atlas crates (copied in)
│   ├── search/             # Hybrid FTS+semantic search
│   ├── indexer/            # Embedding providers + Qdrant
│   ├── analytics/          # Coverage, gaps, duplicates
│   ├── generator/          # LLM card generation
│   ├── validation/         # Card quality pipeline
│   ├── obsidian/           # Vault sync
│   ├── card/               # Card domain model
│   ├── taxonomy/           # Tag normalization
│   ├── database/           # PostgreSQL schema
│   ├── llm/                # LLM provider abstraction
│   ├── rag/                # RAG service
│   ├── ingest/             # PDF/web ingestion
│   ├── knowledge-graph/    # Concept edges
│   ├── cardloop/           # FSRS feedback loop
│   ├── jobs/               # In-process job queue
│   ├── common/             # Shared types/config
│   ├── surface-contracts/  # Shared DTOs
│   └── surface-runtime/    # Service facade
├── bridge/                 # C-ABI FFI for Swift
├── bins/
│   ├── mcp/                # MCP server for Claude Code
│   └── cli/                # CLI for automation
├── ftl/core/               # Fluent translation files
└── AnkiApp/                # Xcode project
    ├── AnkiApp.xcodeproj
    ├── Sources/
    │   ├── Bridge/         # Swift FFI wrappers
    │   ├── Services/       # Async Swift services
    │   ├── Views/          # SwiftUI views
    │   └── Models/         # Swift view models
    └── Proto/              # Generated Swift protobuf types
```

---

## 4. Data Flow Diagrams

### Review Session

```
SwiftUI (ReviewView)
  │  build AnswerCardRequest proto
  ▼
Bridge.shared.command(requestBytes)          // async, off main actor
  │  serialize to protobuf bytes
  ▼
anki_command() [C-ABI]
  ▼
rslib Backend::answer_card()
  │
  ├── Collection::answer_card()
  │     ├── Scheduler::next_states()         // FSRS / SM-2
  │     ├── Card::update state + due date
  │     └── SQLite transaction commit
  │
  └── returns AnswerCardResponse proto bytes
  ▼
Bridge deserializes -> Swift AnswerCardResponse
  ▼
SwiftUI updates view state
```

### Search

```
SwiftUI (SearchView)
  │  build SearchRequest proto (query, deck_filter, limit)
  ▼
Bridge.shared.command(requestBytes)
  ▼
anki_command() [C-ABI]
  ▼
Atlas surface-runtime::search()
  │
  ├── atlas/search::hybrid_search(query)
  │     ├── FTS path:
  │     │     └── PostgreSQL (or SQLite FTS5) full-text query
  │     ├── Semantic path:
  │     │     ├── atlas/indexer::embed(query)   // embedding provider
  │     │     └── Qdrant (embedded) ANN search
  │     └── RRF fusion (Reciprocal Rank Fusion)
  │
  └── returns SearchResponse proto bytes
  ▼
SwiftUI renders ranked card list
```

### Card Generation

```
SwiftUI (GenerateView)
  │  build GenerateCardsRequest proto (source text, deck, options)
  ▼
Bridge.shared.command(requestBytes)
  ▼
anki_command() [C-ABI]
  ▼
Atlas surface-runtime::generate_cards()
  │
  ├── atlas/rag::build_context(source_text)
  │     └── atlas/indexer::embed + Qdrant similarity lookup
  │
  ├── atlas/generator::generate(context, options)
  │     └── atlas/llm::complete()             // provider abstraction
  │           (OpenAI / Anthropic / local Ollama)
  │
  ├── atlas/validation::validate(raw_cards)
  │     └── quality pipeline: duplicates, taxonomy, formatting
  │
  └── atlas/card::register(validated_cards)
        └── persisted to collection store
  ▼
returns GenerateCardsResponse proto bytes
  ▼
SwiftUI shows preview; user confirms import
```

### Sync

```
SwiftUI (SyncView)
  │  build SyncRequest proto
  ▼
Bridge.shared.command(requestBytes)
  ▼
anki_command() [C-ABI]
  ▼
rslib Backend::sync_collection()
  │
  ├── rslib/sync::SyncClient::sync()
  │     ├── HTTP(S) to ankiweb.net or self-hosted sync server
  │     ├── Graves, chunk, finalize protocol
  │     └── local SQLite updated on success
  │
  └── returns SyncResponse proto bytes
  ▼
SwiftUI shows sync status / conflict UI if needed
```

### MCP (Claude Code Integration)

```
Claude Code editor
  │  JSON-RPC over stdio
  ▼
bins/mcp process (separate OS process, not in app)
  │
  ├── MCP tool: search_cards(query)
  │     └── atlas/surface-runtime::search()
  │
  ├── MCP tool: generate_cards(source, options)
  │     └── atlas/surface-runtime::generate_cards()
  │
  ├── MCP tool: get_analytics(deck)
  │     └── atlas/analytics::coverage_report()
  │
  └── MCP tool: sync_obsidian(vault_path)
        └── atlas/obsidian::sync()
  ▼
JSON-RPC response back to Claude Code
```

---

## 5. Crate Dependency Graph

Key dependency relationships (arrows indicate "depends on"):

```
AnkiApp (Swift)
  └── bridge/

bridge/
  ├── rslib/                    (Anki core)
  └── atlas/surface-runtime/   (Atlas facade)

rslib/
  ├── rslib/sync/
  ├── rslib/i18n/
  ├── rslib/io/
  └── rslib/process/

atlas/surface-runtime/
  ├── atlas/search/
  ├── atlas/generator/
  ├── atlas/analytics/
  ├── atlas/obsidian/
  ├── atlas/cardloop/
  └── atlas/jobs/

atlas/search/
  ├── atlas/indexer/
  └── atlas/common/

atlas/indexer/
  ├── atlas/llm/               (for embedding providers)
  └── atlas/common/

atlas/generator/
  ├── atlas/llm/
  ├── atlas/rag/
  ├── atlas/validation/
  └── atlas/card/

atlas/analytics/
  ├── atlas/card/
  ├── atlas/taxonomy/
  └── atlas/database/

atlas/knowledge-graph/
  ├── atlas/card/
  └── atlas/taxonomy/

atlas/cardloop/
  ├── atlas/card/
  └── atlas/surface-contracts/

bins/mcp/
  └── atlas/surface-runtime/

bins/cli/
  ├── rslib/
  └── atlas/surface-runtime/

atlas/common/           (leaf - no atlas deps)
atlas/surface-contracts/ (leaf - no atlas deps)
atlas/card/             (leaf - no atlas deps)
atlas/llm/              (leaf - no atlas deps)
atlas/database/         (leaf - no atlas deps)
```

---

## 6. Infrastructure Decisions

| Component | Server (anki-atlas) | Desktop (this project) | Rationale |
|-----------|--------------------|-----------------------|-----------|
| Redis | Redis 7 (job queue) | `tokio::mpsc` channels | No external process for desktop; in-process channels are sufficient for a single-user app |
| Qdrant | Qdrant 1.16+ server | Embedded mode (`qdrant-client` with `storage_path`) | Local vector storage without a sidecar; embedded mode is stable as of 1.9+ |
| PostgreSQL | PostgreSQL 16 | TBD: `embedded-postgres`, bundled `libpq`, or migrate to SQLite | Biggest open question; `embedded-postgres` adds 50-100 MB to bundle size; SQLite FTS5 covers most atlas query patterns but loses window functions and `pg_trgm` |
| Anki SQLite | Read-only copy via `anki-reader` crate | Direct `Collection` access | `anki-reader` crate is not needed; `rslib` owns the SQLite handle directly |

### PostgreSQL migration decision criteria

The choice between embedded PostgreSQL and SQLite should be made before implementing `atlas/database/`:

- If atlas analytics queries rely on window functions (`LAG`, `LEAD`, `NTILE`) or recursive CTEs, keep PostgreSQL embedded.
- If queries are expressible with SQLite FTS5 + basic aggregates, migrate the schema to SQLite and eliminate the embedded-postgres dependency.
- A hybrid is possible: use SQLite for all relational data, Qdrant embedded for vectors, and remove PostgreSQL entirely.

---

## 7. License

| Component | License |
|-----------|---------|
| Anki `rslib` | AGPL-3.0-or-later |
| anki-atlas | MIT |
| Combined work | AGPL-3.0 (MIT is compatible; MIT-licensed code may be included in AGPL-3.0 works) |
| Mac App Store | Evaluate AGPL compatibility before submission; AGPL requires making source available to users who receive the binary, which conflicts with standard App Store terms unless a source offer is prominently provided outside the store |

The practical path for Mac App Store distribution is either: (a) dual-license negotiation with all `rslib` contributors, or (b) distribute outside the App Store (direct download, Homebrew cask, or Setapp) where AGPL source-offer requirements are straightforward to satisfy.

---

## 8. Toolchain

| Component | Version / Requirement |
|-----------|----------------------|
| Rust edition | 2024 |
| MSRV | 1.92+ |
| Swift | 5.9+ (Swift macros, structured concurrency, `@Observable`) |
| Xcode | 15+ |
| macOS deployment target | 13.0 (Ventura) |
| Protobuf compiler | `protoc` via Homebrew |
| Rust protobuf codegen | `prost` + `prost-build` |
| Swift protobuf codegen | `swift-protobuf` (`protoc-gen-swift`) |
| FFI header generation | `cbindgen` |
| Swift package manager | For `swift-protobuf` and `swift-nio` dependencies |
| Build system | `cargo build` for Rust; Xcode build phases call `cargo` to produce the `.dylib` / `.a` |

### Build integration notes

Xcode calls a build phase script that:

1. Runs `cargo build --release -p bridge` to produce `libbridge.a`.
2. Copies the static library and the `cbindgen`-generated header to `AnkiApp/Sources/Bridge/`.
3. Runs `protoc` with `protoc-gen-swift` to regenerate `AnkiApp/Proto/` from `proto/anki/*.proto`.

The `rslib` protobuf codegen (Rust side) is driven by `build.rs` in `rslib/proto/`, unchanged from the upstream Anki build. The `proto/anki/` directory is the single source of truth for both sides.
