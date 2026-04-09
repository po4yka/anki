# Protobuf API Compatibility

## Overview

The `proto/anki/` directory contains 20 .proto files defining the Rust backend's
RPC interface. Swift calls these via the C-ABI bridge using numeric service/method
IDs and protobuf serialization.

## Service Architecture

Each .proto file defines two service types:
- **BackendXxxService** -- implemented in Rust, callable from Swift
- **XxxService** -- frontend-only stubs (not implemented in backend)

## Versioning Policy

- **Additive changes are safe**: new services, new methods, new message fields
- **Breaking changes require coordination**: removing/renaming fields, changing
  field numbers, removing methods
- Proto changes require regeneration of both Rust types (automatic via build.rs)
  and Swift types (`protoc --swift_out=...`)

## Service Index

| Proto File | Backend Service | Description |
|------------|----------------|-------------|
| backend.proto | (meta) | BackendInit, BackendError definitions |
| cards.proto | BackendCardsService | Card CRUD operations (get, update, remove, set deck/flag) |
| card_rendering.proto | BackendCardRenderingService | Card HTML rendering, LaTeX extraction, TTS, answer comparison |
| collection.proto | BackendCollectionService | Collection lifecycle (open, close, backup), undo/redo, progress |
| config.proto | BackendConfigService | User preferences and typed config key access |
| deck_config.proto | BackendDeckConfigService | Deck scheduling options (steps, intervals, FSRS parameters) |
| decks.proto | BackendDecksService | Deck tree management (add, rename, remove, reparent, filtered decks) |
| generic.proto | (shared types) | Empty, Int32, UInt32, Int64, String, Json, Bool, StringList |
| i18n.proto | BackendI18nService | Localization string translation and timespan formatting |
| image_occlusion.proto | BackendImageOcclusionService | Image occlusion note creation and retrieval |
| import_export.proto | BackendImportExportService | APKG/COLPKG/CSV import and export |
| links.proto | BackendLinksService | Help page URL generation |
| media.proto | BackendMediaService | Media file management (add, check, trash, restore) |
| notes.proto | BackendNotesService | Note CRUD operations and field validation |
| notetypes.proto | BackendNotetypesService | Note type definitions: templates, fields, stock types |
| scheduler.proto | BackendSchedulerService | Card scheduling and review (answer cards, bury/suspend, FSRS) |
| search.proto | BackendSearchService | Search query building, card/note search, browser row rendering |
| stats.proto | BackendStatsService | Review statistics, card history, and graph data |
| sync.proto | BackendSyncService | AnkiWeb synchronization (login, collection sync, media sync) |
| tags.proto | BackendTagsService | Tag management (add, remove, rename, reparent, autocomplete) |

## Empty Frontend Services

The following `XxxService` definitions are frontend-only stubs with no Rust implementation.
They exist to reserve the service slot in the numeric dispatch table:

| Service | File |
|---------|------|
| SyncService | sync.proto |

All other `XxxService` (non-Backend) definitions contain RPC methods that are
forwarded to the corresponding `BackendXxxService` implementation in Rust.

## Regenerating Types

### Rust (automatic)
Rust types are generated automatically by `rslib/proto/build.rs` during `cargo build`.

### Swift
```bash
protoc --swift_out=AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto
```
