# AnkiApp SwiftUI Architecture

The AnkiApp is a native macOS spaced repetition application built with SwiftUI, communicating with a Rust backend via C-ABI FFI.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│ SwiftUI Views (ContentView, DeckBrowserView, etc.)      │
├─────────────────────────────────────────────────────────┤
│ AppState (@Observable) - Singleton state management     │
├─────────────────────────────────────────────────────────┤
│ Bridge Layer                                            │
│  • AnkiService (protobuf RPC)                           │
│  • AtlasService (JSON RPC)                              │
├─────────────────────────────────────────────────────────┤
│ FFI Bridge (C-ABI)                                      │
│  • anki_init, anki_command, anki_free                   │
│  • atlas_init, atlas_command, atlas_free                │
├─────────────────────────────────────────────────────────┤
│ Rust Backend (rslib + atlas crates)                     │
└─────────────────────────────────────────────────────────┘
```

## State Management

AppState is a singleton managed by `@Observable` and marked `@MainActor`. It drives the entire app:

```swift
@Observable
@MainActor
final class AppState {
    var isCollectionOpen: Bool
    var selectedSidebarItem: SidebarItem
    var error: AnkiError?
    var undoStatus: Anki_Collection_UndoStatus?
    
    let service: AnkiService          // Protobuf RPC to Rust
    var atlasService: AtlasService?   // JSON RPC to Atlas
}
```

Pass it via `.environment(appState)` to all child views. Access via `@Environment(AppState.self)`.

## Navigation

Navigation uses a two-view pattern: **SidebarView** + **DetailRouter**.

### SidebarView
Displays 12 navigation items split into Anki (8) and Atlas (4) sections:
- **Anki**: Decks, Browse, Note Types, Image Occlusion, Stats, Import, Export, Sync
- **Atlas**: Search+, Analytics, Generator, Obsidian

Selection binds to `appState.selectedSidebarItem` (a `SidebarItem` enum).

### DetailRouter
Switches on `appState.selectedSidebarItem` and renders the appropriate view:

```swift
struct DetailRouter: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        switch appState.selectedSidebarItem {
            case .decks:
                DeckBrowserView()
            case .browse:
                SearchView()
            // ... 10 more cases
        }
    }
}
```

## Bridge Layer

### AnkiBridge
Low-level C-ABI wrapper around `anki_init`, `anki_command`, `anki_free`:

```swift
class AnkiBridge {
    func command<Output: SwiftProtobuf.Message>(
        service: UInt32, 
        method: UInt32, 
        input: SwiftProtobuf.Message
    ) throws -> Output
}
```

Serializes request to protobuf bytes, calls FFI, deserializes response.

### AnkiService (Actor)
Type-safe service layer wrapping AnkiBridge. Methods:
- `openCollection(path:mediaFolder:mediaDb:)`
- `closeCollection(downgrade:)`
- `undo()`, `redo()`
- `getUndoStatus()`
- Custom methods per domain (decks, notes, templates, etc.)

All methods are async and thread-safe (runs on dedicated actor executor).

### AtlasService (Actor)
JSON RPC to atlas crates. Low-level `command<Resp>` + type-safe methods:

```swift
func search(_ request: SearchRequest) async throws -> SearchResponse
func generatePreview(filePath: String) async throws -> GeneratePreview
func getTaxonomyTree(rootPath: String?) async throws -> [TaxonomyNode]
func getGaps(topicPath: String, minCoverage: Int = 0) async throws -> [TopicGap]
// ... and 4 more
```

## View Structure

```
AnkiApp/
  ├── AnkiApp.swift                 # @main entry point, menu bar
  ├── Views/
  │   ├── ContentView.swift         # Split view (sidebar + detail)
  │   ├── SidebarView.swift         # Navigation enum + sidebar UI
  │   ├── DetailRouter.swift        # Switch on selected item
  │   ├── Decks/
  │   │   ├── DeckBrowserView.swift
  │   │   ├── DeckConfigView.swift
  │   │   └── ...
  │   ├── Search/
  │   ├── Stats/
  │   └── ... (other features)
  ├── Models/
  │   ├── AppState.swift            # Singleton state
  │   ├── *Model.swift              # Per-feature models (SearchModel, SyncModel, etc.)
  │   └── ...
  └── Bridge/
      ├── AnkiBridge.swift          # C-ABI wrapper
      ├── AnkiService.swift         # Type-safe Anki RPC
      └── AtlasService.swift        # Type-safe Atlas RPC
```

Naming: `[Feature]View.swift` for SwiftUI views, `[Feature]Model.swift` for data/logic.

## Adding a New View

1. **Create the view** in `Views/[Feature]/[Feature]View.swift`:
   ```swift
   struct MyFeatureView: View {
       @Environment(AppState.self) private var appState
       
       var body: some View {
           // Your UI here
       }
   }
   ```

2. **Create a model** if needed in `Models/[Feature]Model.swift`:
   ```swift
   @Observable
   final class MyFeatureModel {
       var data: SomeType
       
       func loadData() async {
           // Use appState.service or appState.atlasService
       }
   }
   ```

3. **Add a sidebar item** in `Views/SidebarView.swift`:
   ```swift
   enum SidebarItem {
       case myFeature = "My Feature"
       
       var systemImage: String {
           case .myFeature: "star"
       }
   }
   ```

4. **Add to sidebar arrays** (ankiItems or atlasItems in SidebarView).

5. **Add routing** in `DetailRouter.swift`:
   ```swift
   case .myFeature:
       MyFeatureView()
   ```

## Building

### Prerequisites
```bash
brew install protobuf
brew install swift-protobuf
```

### Build Rust bridge
```bash
cargo build -p anki_bridge
```

### Open in Xcode
```bash
open AnkiApp/AnkiApp.xcodeproj
```

Xcode will:
1. Detect the Rust staticlib from `Bridge/` build phase
2. Link `libanki_bridge.a` + `libatlas.a`
3. Include C header from `bridge/cbridge.h`

### Verify linking
If you see `anki_init not found`, rebuild the Rust bridge:
```bash
cargo build -p anki_bridge --release
cargo build -p anki_bridge  # debug
```

## Testing

### SwiftUI Previews
Add to any view:
```swift
#Preview {
    MyFeatureView()
        .environment(AppState())
}
```

### Unit Tests
Place in `Tests/AnkiAppTests/`:
```swift
@Test
func myTest() {
    let state = AppState()
    // Test state mutations and service calls
}
```

### Quick iteration
- Run `cargo check -p anki_bridge` for Rust errors
- Press Cmd+B in Xcode for incremental SwiftUI builds
- Use previews for immediate visual feedback

## Key Patterns

- **Singletons**: AppState is the sole source of truth. No globals or instance variables in views.
- **Error handling**: `AnkiError.backend()` for Rust errors, `AnkiError.message()` for client errors.
- **Async/await**: All RPC calls are async. Wrap in `Task { }` in view event handlers.
- **Environment**: Pass AppState, models, and settings via `.environment()`, never as init parameters.
- **Actors**: AnkiService and AtlasService are actors; their methods are automatically serialized.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `anki_init not found` | Rebuild Rust bridge: `cargo build -p anki_bridge` |
| `BackendError` in logs | Check Rust backend error message in AppState.error |
| Preview crashes | Ensure AppState() is passed to preview |
| Build hangs | Kill Xcode, run `cargo clean`, rebuild |

