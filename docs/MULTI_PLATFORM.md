# Multi-Platform Strategy

## Overview

The Anki SwiftUI app is designed for cross-platform Apple deployment:

- **macOS** -- full-featured, local processing (current)
- **iPadOS** -- sidebar navigation, remote atlas (future)
- **iOS** -- tab-based navigation, remote atlas (future)

## Architecture

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  macOS App   │  │  iPad App    │  │  iPhone App  │
│  Sidebar +   │  │  Sidebar +   │  │  TabBar +    │
│  Detail      │  │  Detail      │  │  NavStack    │
├──────────────┴──┴──────────────┴──┴──────────────┤
│  Shared SwiftUI Views + @Observable Models       │
├──────────────────────────────────────────────────┤
│  AnkiService (protobuf FFI) -- same on all       │
│  AtlasServiceProtocol                            │
│    ├── AtlasService (FFI, macOS)                 │
│    └── RemoteAtlasService (HTTP, iOS/iPadOS)     │
├──────────────────────────────────────────────────┤
│  Rust staticlib (XCFramework)                    │
│  rslib + bridge + ffi_common                     │
├──────────────────────────────────────────────────┤
│  Storage                                         │
│    ├── SQLite (rslib, all platforms)              │
│    ├── PostgreSQL + pgvector (macOS/server)       │
│    └── SQLite vectors (iOS, brute-force cosine)   │
└──────────────────────────────────────────────────┘
```

## Storage Backends

### Anki Core (rslib) -- SQLite everywhere

The core flashcard engine uses SQLite for card/note/deck storage.
This works identically on all Apple platforms via rusqlite (bundled).

### Atlas Features -- platform-dependent

| Platform | Storage | Vector Search | Atlas Access |
|----------|---------|---------------|--------------|
| macOS | PostgreSQL + pgvector | HNSW index (fast) | Local FFI |
| iPadOS | SQLite | Brute-force cosine | Remote HTTP or local |
| iOS | SQLite | Brute-force cosine | Remote HTTP |

## Components

### AtlasServiceProtocol

Swift protocol enabling platform-specific atlas implementations:

```swift
protocol AtlasServiceProtocol: Sendable {
    func search(_ request: SearchRequest) async throws -> SearchResponse
    func generatePreview(filePath: String) async throws -> GeneratePreviewResponse
    func getTaxonomyTree(rootPath: String?) async throws -> [TaxonomyNode]
    // ... 9 typed methods total
}
```

All Atlas models (`AtlasSearchModel`, `AnalyticsModel`, `CardGeneratorModel`,
`ObsidianModel`) use `any AtlasServiceProtocol`, not the concrete type.

### anki-atlas-server

Axum HTTP server (`bins/server/`) exposing surface-runtime methods for
remote clients. 9 JSON POST endpoints + health check:

```
POST /api/search              -- hybrid search
POST /api/search_chunks       -- chunk-level search
POST /api/get_taxonomy_tree   -- topic taxonomy
POST /api/get_coverage        -- topic coverage
POST /api/get_gaps            -- gap detection
POST /api/get_weak_notes      -- weak notes
POST /api/find_duplicates     -- duplicate detection
POST /api/generate_preview    -- card generation
POST /api/obsidian_scan       -- vault scanning
GET  /health                  -- health check
```

Configuration via `ANKIATLAS_API_HOST` and `ANKIATLAS_API_PORT`.

### SqliteVectorRepository

SQLite-backed `VectorRepository` for mobile (`atlas/database/src/sqlite_vector.rs`).
Stores embeddings as little-endian f32 blobs, brute-force cosine similarity
search. Suitable for collections up to ~100k notes.

```rust
let repo = SqliteVectorRepository::new("vectors.db")?;
repo.ensure_collection(384).await?;
repo.upsert_vectors(&embeddings, &payloads).await?;
let results = repo.search_chunks(&query_vec, Some("search text"), 10, &filters).await?;
```

## Build Targets

```bash
# macOS (current)
cargo build -p anki_bridge --release

# iOS (future)
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
cargo build -p anki_bridge --target aarch64-apple-ios --release

# XCFramework (future)
xcodebuild -create-xcframework \
  -library target/aarch64-apple-darwin/release/libanki_bridge.a \
  -library target/aarch64-apple-ios/release/libanki_bridge.a \
  -output AnkiBridge.xcframework
```

## UI Adaptation

| Component | macOS | iPad | iPhone |
|-----------|-------|------|--------|
| Navigation | Sidebar + Detail | Sidebar + Detail | TabBar + NavStack |
| File Picker | NSSavePanel | .fileImporter | .fileImporter |
| Search Table | Table (columns) | List | List |
| Settings | Settings scene | In-app view | In-app view |
| Window Mgmt | Multi-window | Single | Single |

### Platform Guards

macOS-specific code uses `#if os(macOS)` guards:

```swift
#if os(macOS)
import AppKit
// NSSavePanel, NSOpenPanel usage
#else
import UIKit
// .fileImporter modifier
#endif
```

## Sync Strategy

```
┌─────────┐    AnkiWeb     ┌─────────┐
│  macOS  │ ◄────────────► │ AnkiWeb │
│  App    │    (protobuf)   │ Server  │
├─────────┤                 └─────────┘
│  Atlas  │                 
│ Server  │ ◄── HTTP JSON ── iOS App
│ (axum)  │                 
└─────────┘
```

- **Anki core sync**: All platforms sync directly with AnkiWeb
- **Atlas sync**: iOS connects to the atlas HTTP server (user's macOS or cloud)
- **Offline**: Core SRS features work offline on all platforms; atlas features
  require server connectivity on iOS
