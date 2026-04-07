# Protobuf Workflow

## Overview

Adding a new RPC requires changes across Rust, protobuf, and Swift layers.
Follow these steps in order.

## Steps to Add a New RPC

### 1. Edit the Proto File

Edit or create a `.proto` file in `proto/anki/`:

```protobuf
service DeckService {
    rpc GetDeck (GetDeckRequest) returns (GetDeckResponse);
}

message GetDeckRequest {
    int64 deck_id = 1;
}

message GetDeckResponse {
    Deck deck = 1;
}
```

### 2. Build Rust (Auto-generates)

```bash
cargo build --workspace
```

The `build.rs` in the bridge crate auto-generates Rust types from `.proto` files.

### 3. Generate Swift Types

```bash
protoc --swift_out=AnkiApp/AnkiApp/AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto
```

### 4. Add Method Index to ServiceConstants

In `AnkiApp/.../ServiceConstants.swift`, add the method index that maps
to the protobuf service/method pair:

```swift
enum DeckService {
    static let getDeck: UInt32 = 0
}
```

### 5. Add to AnkiServiceProtocol

Define the Swift-side protocol method:

```swift
protocol AnkiServiceProtocol {
    func getDeck(id: Int64) async throws -> Deck
}
```

### 6. Implement in AnkiService

Implement using the bridge FFI:

```swift
func getDeck(id: Int64) async throws -> Deck {
    var req = Anki_GetDeckRequest()
    req.deckID = id
    let data = try await callBridge(service: .deck, method: DeckService.getDeck, request: req)
    return try Anki_GetDeckResponse(serializedBytes: data).deck
}
```

### 7. Wire to ViewModel

Connect the service method to the UI layer through a ViewModel.

## When to Use

- Adding new backend functionality exposed to Swift
- Modifying existing protobuf service definitions
- Debugging proto serialization mismatches
