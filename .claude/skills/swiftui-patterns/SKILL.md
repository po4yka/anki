# SwiftUI Patterns

## Overview

The SwiftUI layer in `AnkiApp/` follows modern Swift conventions targeting
macOS with the latest APIs.

## Observable Pattern

Use `@Observable` macro (Observation framework), **not** `ObservableObject`:

```swift
@Observable
final class DeckViewModel {
    var decks: [Deck] = []
    var isLoading = false
}
```

In views, access via `@State` for owned state or `@Environment` for injected:

```swift
struct DeckListView: View {
    @State private var viewModel = DeckViewModel()
    var body: some View { ... }
}
```

## Navigation

Use `NavigationSplitView` for sidebar layouts:

```swift
NavigationSplitView {
    SidebarView()
} detail: {
    DetailView()
}
```

## Previews

Use the `#Preview` macro:

```swift
#Preview {
    DeckListView()
}
```

## Async/Await and Actors

- Use `async/await` for all async work
- Use actors for thread-safe mutable state
- No Combine -- use `AsyncSequence` instead

## Testing

Use Swift Testing framework (`@Test`, `#expect`), **not** XCTest:

```swift
@Test func deckCountUpdates() async {
    let vm = DeckViewModel()
    await vm.loadDecks()
    #expect(vm.decks.count > 0)
}
```

## Style Rules

- One type per file
- Views under 100 lines -- extract subviews
- Use SF Symbols for icons
- Use system semantic colors (not hardcoded)
- No force-unwrap (`!`) in production code

## When to Use

- Creating or modifying SwiftUI views in `AnkiApp/`
- Reviewing Swift code for convention compliance
- Migrating from ObservableObject to @Observable
