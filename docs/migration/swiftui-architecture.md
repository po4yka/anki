# SwiftUI App Architecture -- Phase 3

This document defines the SwiftUI application architecture for the Anki macOS
client. It covers navigation, state management, data flow, view hierarchy,
card rendering, service mapping, error handling, and testing.

Target: macOS 13+ (Ventura). Swift 5.9+. Xcode 15+.

---

## 1. App Structure

The app uses `NavigationSplitView` with a two-column layout: a fixed sidebar
for top-level navigation and a detail area that switches based on selection.

```swift
@main
struct AnkiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            AnkiCommands()
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailRouter()
        }
    }
}
```

### Window scenes

| Scene | Purpose |
|-------|---------|
| Main `WindowGroup` | Sidebar + detail (deck browser, reviewer, search) |
| `Window("Add Note", id: "add-note")` | Standalone note editor |
| `Settings` | Preferences pane |

---

## 2. Data Flow

All SwiftUI views communicate with the Rust backend exclusively through the
`AnkiService` actor defined in `AnkiApp/Bridge/AnkiService.swift`. No view
ever touches `AnkiBackend` or raw protobuf types directly.

```
View (@Observable model) --async call--> AnkiService (actor)
    --> AnkiBackend.command(service:method:input:) [generic protobuf]
    --> anki_command() [C-ABI FFI]
    --> Backend::run_service_method() [Rust dispatch]
    --> return protobuf bytes
    --> AnkiBackend deserializes to typed Swift proto message
    --> AnkiService returns typed result
    --> @Observable model updates @MainActor published properties
    --> SwiftUI re-renders
```

### Concurrency rules

- `AnkiService` is an `actor` -- all backend calls are serialized.
- View models are `@Observable @MainActor` classes. They call `AnkiService`
  methods from `Task {}` blocks.
- The backend pointer is thread-safe (`Arc<Mutex<...>>` on Rust side), so
  actor serialization is a Swift-level safety layer, not a Rust requirement.

---

## 3. State Management

### AppState -- application-level singleton

```swift
@Observable
@MainActor
final class AppState {
    let service: AnkiService

    // Navigation
    var selectedSidebarItem: SidebarItem = .decks
    var selectedDeckId: Int64?

    // Collection lifecycle
    private(set) var isCollectionOpen = false
    private(set) var collectionError: AnkiError?

    init() {
        do {
            self.service = try AnkiService(langs: Locale.preferredLanguages)
        } catch {
            fatalError("Failed to initialize Anki backend: \(error)")
        }
    }

    func openCollection(at path: String) async {
        let mediaFolder = (path as NSString)
            .deletingLastPathComponent + "/collection.media"
        let mediaDb = mediaFolder + "/media.db"
        do {
            try await service.openCollection(
                path: path, mediaFolder: mediaFolder, mediaDb: mediaDb
            )
            isCollectionOpen = true
        } catch {
            collectionError = error as? AnkiError
        }
    }

    func closeCollection() async {
        try? await service.closeCollection(downgrade: false)
        isCollectionOpen = false
    }
}
```

### Per-screen view models

Each major screen has its own `@Observable @MainActor` class that holds
screen-specific state and calls `AnkiService`. View models receive the
service via `init(service:)` and are created by the parent view or AppState.

| View Model | Owns | Source of Truth |
|------------|------|-----------------|
| `DeckBrowserModel` | `DeckTreeNode` tree, selection | `DecksService.DeckTree` |
| `ReviewerModel` | current `QueuedCard`, counts, answer state | `SchedulerService.GetQueuedCards` |
| `NoteEditorModel` | `Note`, `Notetype`, field values, tags | `NotesService`, `NotetypesService` |
| `SearchModel` | query string, result IDs, `BrowserRow` list | `SearchService` |
| `StatsModel` | `GraphsResponse`, `CardStatsResponse` | `StatsService` |
| `SyncModel` | `SyncCollectionResponse`, progress | `BackendSyncService` |

### When to use @State vs @Observable

- `@State`: view-local UI state (text field contents, toggle state, sheet
  presentation). Never persists beyond the view's lifetime.
- `@Observable` class: any state that (a) is shared between views,
  (b) requires async loading, or (c) survives navigation changes.
- `@Environment(AppState.self)`: injected at the root, available everywhere.

---

## 4. Navigation

### Sidebar items

```swift
enum SidebarItem: String, CaseIterable, Identifiable {
    case decks = "Decks"
    case browse = "Browse"
    case stats = "Statistics"
    case sync = "Sync"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .decks: "rectangle.stack"
        case .browse: "magnifyingglass"
        case .stats: "chart.bar"
        case .sync: "arrow.triangle.2.circlepath"
        }
    }
}
```

### Detail routing

```swift
struct DetailRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSidebarItem {
        case .decks:
            DeckBrowserView()
        case .browse:
            SearchView()
        case .stats:
            StatisticsView()
        case .sync:
            SyncView()
        }
    }
}
```

### Review session entry

Selecting a deck in `DeckBrowserView` and clicking "Study" navigates into a
full-screen `ReviewerView` presented as a sheet or navigation destination.

---

## 5. View Hierarchy -- File/Folder Structure

```
AnkiApp/
  Bridge/
    AnkiBridge.h
    AnkiBridge.swift
    AnkiService.swift
    ServiceConstants.swift        // service/method index enums
  Proto/                          // generated Swift protobuf types
  Models/
    AppState.swift
    DeckBrowserModel.swift
    ReviewerModel.swift
    NoteEditorModel.swift
    SearchModel.swift
    StatsModel.swift
    SyncModel.swift
  Views/
    ContentView.swift
    SidebarView.swift
    DetailRouter.swift
    DeckBrowser/
      DeckBrowserView.swift       // deck list + counts
      DeckRowView.swift           // single deck row
      DeckOptionsSheet.swift      // deck config editor
    Reviewer/
      ReviewerView.swift          // main review screen
      CardWebView.swift           // WKWebView wrapper
      AnswerBar.swift             // Again/Hard/Good/Easy buttons
      ReviewProgress.swift        // remaining count bar
      CongratsView.swift          // session complete
    NoteEditor/
      NoteEditorView.swift        // field-per-notetype layout
      FieldEditorView.swift       // single rich-text field
      TagEditor.swift             // tag input with autocomplete
      DeckPicker.swift            // deck selector dropdown
      NotetypePicker.swift        // notetype selector dropdown
    Search/
      SearchView.swift            // search bar + results
      SearchResultRow.swift       // single result row
      BrowserColumnView.swift     // column-mode table
    Statistics/
      StatisticsView.swift        // chart container
      ReviewChart.swift           // review count/time charts
      ForecastChart.swift         // future due chart
      CardCountsChart.swift       // card state breakdown
    Sync/
      SyncView.swift              // sync button + progress
      SyncConflictSheet.swift     // full sync resolution
    Settings/
      PreferencesView.swift       // collection path, language, etc.
    Components/
      ErrorAlert.swift            // reusable error alert modifier
      LoadingOverlay.swift        // spinner overlay
  Resources/
    reviewer.html                 // card rendering template
    reviewer.css                  // base reviewer styles
    reviewer.js                   // bridge JS for card display
  AnkiApp.swift                   // @main entry point
```

---

## 6. Key Views

### 6a. DeckBrowserView

Displays the deck tree from `DecksService.DeckTree` (`decks.proto:19`).
The `DeckTreeNode` message provides `deck_id`, `name`, `level`, `collapsed`,
`review_count`, `learn_count`, `new_count`, `children` (recursive), and
`filtered` flag.

Renders as a recursive `List` with `DisclosureGroup` for parent decks.
Each row shows new/learn/review counts in colored badges.

### 6b. ReviewerView

Drives the review session using two scheduler RPCs:

1. `GetQueuedCards` (`scheduler.proto:18`) -- fetches a batch of cards
   with scheduling states and rendered HTML.
2. `AnswerCard` (`scheduler.proto:19`) -- submits the user's rating.

The model maintains a local card queue, prefetching when running low.
`showAnswer()` flips from question to answer display. `answer(rating)`
submits the response and advances to the next card.

### 6c. NoteEditorView

Uses `NotesService` and `NotetypesService` for CRUD. The editor dynamically
creates one `FieldEditorView` per field in the notetype's `fields` array,
using the field's `config.font_name`, `config.font_size`, and `config.rtl`.

### 6d. SearchView

Uses `SearchService.SearchCards`/`SearchNotes` with `SearchRequest`
containing the query string and `SortOrder`. Results table uses `Table`
(macOS 13+) with columns from `BrowserColumns.Column`.

### 6e. StatisticsView

Uses `StatsService.Graphs` with `GraphsRequest`. `GraphsResponse` contains
pre-computed data for reviews, future_due, card_counts, hours, intervals,
stability, and retrievability. Charts rendered with Swift Charts (macOS 13+).

---

## 7. Card Rendering

Anki cards are HTML+CSS with media references. The reviewer renders them
in a WKWebView.

```swift
struct CardWebView: NSViewRepresentable {
    let html: String
    let css: String
    let baseURL: URL?  // media folder for images and audio

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let fullHTML = buildReviewerHTML(body: html, css: css)
        webView.loadHTMLString(fullHTML, baseURL: baseURL)
    }
}
```

Card HTML comes from `RenderExistingCard` (`card_rendering.proto:18-19`)
returning `RenderCardResponse` with `question_nodes`/`answer_nodes` (list
of `RenderedTemplateNode`) and `css`. JavaScript in `reviewer.js` receives
card content via `webView.evaluateJavaScript()`.

The `baseURL` is set to the collection's media folder so image and audio
references resolve correctly.

---

## 8. Service Constants

Service and method indices are assigned by the protobuf descriptor pool
order, generated at Rust build time. Define a `ServiceConstants.swift`
file with enums matching the generated dispatch.

To extract indices: build the Rust crate, inspect the generated
`backend.rs` in `target/*/build/anki-*/out/backend.rs`. The
`run_service_method` match arms list service indices; each
`run_{service}_method` lists method indices.

Long-term: automate this with a build script that parses
`anki_descriptors.bin` and generates `ServiceConstants.swift`.

---

## 9. Error Handling

`BackendError` (`backend.proto:24-62`) carries a localized `message`,
`kind` enum, optional `help_page`, and `context`. A reusable
`.ankiErrorAlert($model.error)` view modifier presents errors as native
macOS alerts.

| BackendError.Kind | User action |
|-------------------|-------------|
| `NETWORK_ERROR`, `SYNC_AUTH_ERROR` | Retry + check connection |
| `DB_ERROR` | Suggest "Check Database" |
| `INVALID_INPUT` | Inline validation message |
| `NOT_FOUND_ERROR` | Refresh view |
| `INTERRUPTED` | Silent (user-initiated abort) |

---

## 10. Testing Strategy

Extract `AnkiServiceProtocol` so views can use a `MockAnkiService` actor
for SwiftUI previews and unit tests. Each view file includes a `#Preview`
block using the mock. Integration tests use a real `AnkiService` with a
test `.anki2` collection.

---

## Appendix: Implementation Order

1. `ServiceConstants.swift` + extend `AnkiService` with typed methods
2. `AppState` + `ContentView` + `SidebarView` + `DetailRouter`
3. Collection open/close flow in `AppState`
4. `DeckBrowserView` + `DeckBrowserModel`
5. `CardWebView` + `reviewer.html/css/js`
6. `ReviewerView` + `ReviewerModel`
7. `NoteEditorView` + `NoteEditorModel`
8. `SearchView` + `SearchModel`
9. `StatisticsView` + `StatsModel`
10. `SyncView` + `SyncModel`
11. Import/export, deck options, preferences
