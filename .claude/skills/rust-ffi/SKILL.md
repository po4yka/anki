# Rust FFI Bridge Patterns

## Overview

The `bridge/` crate provides a C-ABI interface between Rust and Swift using
protobuf serialization. All cross-language calls go through three entry points.

## Entry Points

```rust
#[no_mangle]
pub extern "C" fn anki_init(bytes: *const u8, len: usize) -> *mut Backend
```
Creates a Backend instance from a protobuf-serialized `BackendInit` message.

```rust
#[no_mangle]
pub extern "C" fn anki_command(
    backend: *mut Backend,
    service: u32,
    method: u32,
    bytes: *const u8,
    len: usize,
) -> ByteBuffer
```
Dispatches an RPC call. Service and method indices map to protobuf service definitions.

```rust
#[no_mangle]
pub extern "C" fn anki_free(backend: *mut Backend)
```
Releases the Backend and all associated resources.

## ByteBuffer Pattern

```rust
#[repr(C)]
pub struct ByteBuffer {
    data: *mut u8,
    len: usize,
}
```
- Allocated on the Rust side, freed by the caller via `anki_free_buf()`
- Contains protobuf-serialized response data
- Never access after freeing

## Safety Rules

- **No panics across FFI**: Wrap all entry points in `catch_unwind`
- **Opaque pointers**: Swift sees `OpaquePointer`, never dereferences Rust types
- **Memory ownership**: Rust allocates, Swift must call the matching free function
- **No `String` across FFI**: Use `*const u8` + length, not CString
- **Thread safety**: Backend is `Send + Sync`, safe to call from any thread

## Protobuf Serialization

Request flow:
1. Swift serializes a protobuf message to `Data`
2. Passes `data.baseAddress` and `data.count` to the C function
3. Rust deserializes with `prost::Message::decode()`
4. Rust serializes the response and returns a `ByteBuffer`
5. Swift reads the buffer into `Data` and deserializes

## When to Use

- Adding new FFI functions to `bridge/`
- Debugging serialization errors between Swift and Rust
- Understanding memory ownership at the language boundary
