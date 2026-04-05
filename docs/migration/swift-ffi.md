# Swift FFI Bridge Design for Anki's Rust Backend

This document describes the recommended approach for calling Anki's Rust backend
from a SwiftUI application. It covers the bridge crate design, Swift-side wrapper
code, proto generation, Xcode integration, and memory safety considerations.

## Overview

The recommended approach is **Protobuf-over-C-ABI**: a thin Rust staticlib exposes
three C functions, all complex types cross the boundary as serialized protobuf bytes,
and Swift generates rich typed access from the same `.proto` files via swift-protobuf.

This mirrors the existing Python bridge in `pylib/rsbridge/lib.rs`, which uses the
identical pattern in production today.

## Recommended Approach: Protobuf-over-C-ABI

### Why this approach

- Anki's entire API is already protobuf-defined across 24 `.proto` files in `proto/anki/`.
- The same pattern is battle-tested in production for the Python bridge (`pylib/rsbridge`).
- The FFI surface area is minimal: 3 functions plus memory management.
- Swift gets rich, fully-typed access via swift-protobuf generated code.
- No additional IDL or binding generators are needed.

### High-level data flow

```
SwiftUI view
    |
    v
AnkiService (actor)        — typed async wrapper, one method per RPC
    |
    v
AnkiBackend (class)        — serializes/deserializes protobuf, manages backend ptr
    |
    v  (C ABI over staticlib)
anki_command(ptr, service, method, input_bytes) -> ByteBuffer
    |
    v
Backend::run_service_method — dispatches to the correct service handler in rslib
```

## Rust Bridge Crate

Create a new crate `bridge/` at the root of the repository alongside `rslib/`.

### `bridge/Cargo.toml`

```toml
[package]
name = "anki_bridge"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["staticlib"]    # produces libanki_bridge.a

[dependencies]
anki = { path = "../rslib" }
```

### `bridge/src/lib.rs`

```rust
use std::ffi::c_void;
use std::slice;

use anki::backend::{init_backend, Backend};

/// Byte buffer for transferring owned data across the FFI boundary.
/// Swift must call anki_free_buffer() when it is done with the data.
#[repr(C)]
pub struct ByteBuffer {
    data: *mut u8,
    len: usize,
}

impl ByteBuffer {
    fn from_vec(v: Vec<u8>) -> Self {
        let mut v = v.into_boxed_slice();
        let buf = ByteBuffer {
            data: v.as_mut_ptr(),
            len: v.len(),
        };
        std::mem::forget(v);
        buf
    }

    fn empty() -> Self {
        ByteBuffer {
            data: std::ptr::null_mut(),
            len: 0,
        }
    }
}

/// Initialize a Backend from a serialized BackendInit protobuf message.
///
/// Returns an opaque pointer on success. The caller must pass this pointer to
/// all subsequent anki_command calls and must call anki_free() when done.
/// Returns null on error.
#[no_mangle]
pub extern "C" fn anki_init(
    data: *const u8,
    len: usize,
) -> *mut c_void {
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    match init_backend(bytes) {
        Ok(backend) => Box::into_raw(Box::new(backend)) as *mut c_void,
        Err(_) => std::ptr::null_mut(),
    }
}

/// Execute a protobuf service method.
///
/// On success, is_error is set to false and the returned ByteBuffer contains
/// the serialized protobuf response. On error, is_error is set to true and
/// the returned ByteBuffer contains a serialized BackendError message.
///
/// The returned ByteBuffer must be freed with anki_free_buffer().
#[no_mangle]
pub extern "C" fn anki_command(
    backend: *mut c_void,
    service: u32,
    method: u32,
    input: *const u8,
    input_len: usize,
    is_error: *mut bool,
) -> ByteBuffer {
    let backend = unsafe { &*(backend as *const Backend) };
    let input_bytes = unsafe { slice::from_raw_parts(input, input_len) };
    match backend.run_service_method(service, method, input_bytes) {
        Ok(response) => {
            unsafe { *is_error = false };
            ByteBuffer::from_vec(response)
        }
        Err(err_bytes) => {
            unsafe { *is_error = true };
            ByteBuffer::from_vec(err_bytes)
        }
    }
}

/// Free a Backend instance created by anki_init.
#[no_mangle]
pub extern "C" fn anki_free(backend: *mut c_void) {
    if !backend.is_null() {
        unsafe { drop(Box::from_raw(backend as *mut Backend)) };
    }
}

/// Free a ByteBuffer returned by anki_command.
#[no_mangle]
pub extern "C" fn anki_free_buffer(buf: ByteBuffer) {
    if !buf.data.is_null() {
        unsafe {
            drop(Box::from_raw(slice::from_raw_parts_mut(buf.data, buf.len)));
        };
    }
}
```

## Swift Side

### `AnkiBridge.h` (bridging header)

```c
#ifndef AnkiBridge_h
#define AnkiBridge_h

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint8_t *data;
    size_t len;
} ByteBuffer;

void *anki_init(const uint8_t *data, size_t len);
ByteBuffer anki_command(void *backend, uint32_t service, uint32_t method,
                        const uint8_t *input, size_t input_len, bool *is_error);
void anki_free(void *backend);
void anki_free_buffer(ByteBuffer buf);

#endif
```

### `AnkiBridge.swift`

`AnkiBackend` is a low-level class that owns the opaque backend pointer and handles
serialization. It should not be used directly from UI code.

```swift
import Foundation
import SwiftProtobuf

enum AnkiError: Error {
    case initFailed
    case backend(Anki_Backend_BackendError)
    case decodingFailed(Error)
}

class AnkiBackend {
    private let ptr: UnsafeMutableRawPointer

    init(preferredLangs: [String], server: Bool = false) throws {
        var initMsg = Anki_Backend_BackendInit()
        initMsg.preferredLangs = preferredLangs
        initMsg.server = server
        let data = try initMsg.serializedData()

        let backend = data.withUnsafeBytes { bytes in
            anki_init(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
        }
        guard let backend else {
            throw AnkiError.initFailed
        }
        self.ptr = backend
    }

    func command<Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message>(
        service: UInt32,
        method: UInt32,
        input: Input
    ) throws -> Output {
        let inputData = try input.serializedData()
        var isError = false

        let buffer = inputData.withUnsafeBytes { bytes in
            anki_command(
                ptr, service, method,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &isError
            )
        }
        defer { anki_free_buffer(buffer) }

        let outputData = Data(bytes: buffer.data, count: buffer.len)

        if isError {
            let backendError = try Anki_Backend_BackendError(serializedBytes: outputData)
            throw AnkiError.backend(backendError)
        }
        return try Output(serializedBytes: outputData)
    }

    deinit {
        anki_free(ptr)
    }
}
```

### `AnkiService.swift` — typed async wrapper

`AnkiService` is declared as a Swift `actor` so all calls are serialized through
Swift's concurrency system. Add one method per protobuf RPC you need to call.

```swift
actor AnkiService {
    private let backend: AnkiBackend

    init(langs: [String] = ["en"]) throws {
        self.backend = try AnkiBackend(preferredLangs: langs)
    }

    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = path
        req.mediaFolderPath = mediaFolder
        req.mediaDbPath = mediaDb
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.openCollection,
            input: req
        )
    }

    func getCard(id: Int64) async throws -> Anki_Cards_Card {
        var req = Anki_Cards_GetCardRequest()
        req.cardID = id
        return try backend.command(
            service: ServiceIndex.cards,
            method: CardsMethod.getCard,
            input: req
        )
    }

    // Add further typed methods wrapping each protobuf service as needed.
}
```

Service and method index constants must match the values generated by the Anki build
system. Inspect `out/pylib/anki/_backend_generated.py` or the generated TypeScript
module at `out/ts/lib/generated/` to find the numeric values for each service and
method.

## Proto Generation for Swift

Install the swift-protobuf plugin and generate Swift types from the `.proto` files:

```bash
# Install the protoc Swift plugin
brew install swift-protobuf

# Generate Swift types from all Anki proto files
protoc --swift_out=AnkiApp/Proto/ \
       --proto_path=proto/ \
       proto/anki/*.proto
```

Add the generated files to your Xcode target. The `SwiftProtobuf` package must also
be added as a Swift Package Manager dependency:

```
https://github.com/apple/swift-protobuf.git  (version 1.x)
```

## Xcode Build Integration

1. Build the Rust staticlib:

   ```bash
   cargo build --release -p anki_bridge
   # Output: target/release/libanki_bridge.a
   ```

2. In Xcode, open the target's **Build Phases** tab:
   - **Link Binary With Libraries**: add `libanki_bridge.a`
   - **Library Search Paths**: add `$(PROJECT_DIR)/../target/release`

3. In **Build Settings**, set **Objective-C Bridging Header** to the path of
   `AnkiBridge.h`.

4. Optionally add a **Run Script** build phase before **Compile Sources** to
   auto-build the Rust crate whenever Xcode builds the Swift target:

   ```bash
   cd "$PROJECT_DIR/.."
   cargo build --release -p anki_bridge
   ```

## Alternatives Considered

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **Protobuf-over-C-ABI** (recommended) | Minimal FFI surface, battle-tested in Anki's Python bridge, rich Swift types via swift-protobuf | Manual C header, explicit memory management | Best fit — Anki already uses this pattern |
| **UniFFI** | Auto-generates Swift bindings, handles memory, supports rich types natively | Adds UDL/proc-macro layer, does not leverage the existing proto API, heavier build pipeline | Overkill — protobuf already defines the full API surface |
| **swift-bridge** | Direct Rust-Swift type interop, no C header required | Less mature ecosystem, would require redefining the entire API surface | Unnecessary complexity for an already-protobuf API |
| **cbindgen** | Auto-generates the C header from Rust attributes | Same outcome as the manual header but adds a build dependency | Minor ergonomics win, not worth the added complexity |

## Memory Safety

- The backend pointer passed to `anki_command` is opaque from Swift's perspective.
  Swift never dereferences it, only passes it back to the C functions.
- `ByteBuffer` ownership transfers to Swift on return from `anki_command`. Swift is
  responsible for calling `anki_free_buffer()`, which `AnkiBackend.command` does via
  a `defer` block.
- All protobuf serialization happens independently on each side of the boundary.
  There is no shared mutable memory between Swift and Rust during a call.
- `Backend` is internally thread-safe (`Arc<Mutex<...>>`). It is safe to call
  `anki_command` from any thread, though the `actor` wrapper in `AnkiService`
  provides an additional Swift-level serialization guarantee.
- The `deinit` on `AnkiBackend` calls `anki_free`, which drops the `Box<Backend>` on
  the Rust side. Do not call any C functions after `AnkiBackend` has been deinitialized.
