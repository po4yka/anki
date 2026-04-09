// This crate is a C-ABI FFI bridge. It inherently requires unsafe code for raw
// pointer handling and #[no_mangle] exports.
#![allow(unsafe_code)]
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::c_void;
use std::slice;

use anki::backend::{Backend, init_backend};
use ffi_common::ByteBuffer;

/// Initialize a Backend from a serialized BackendInit protobuf message.
///
/// Returns an opaque pointer on success. The caller must pass this pointer to
/// all subsequent anki_command calls and must call anki_free() when done.
/// Returns null on error or if a panic occurs.
#[unsafe(no_mangle)]
pub extern "C" fn anki_init(data: *const u8, len: usize) -> *mut c_void {
    ffi_common::catch_ffi_panic(|| {
        // SAFETY: `data` points to `len` bytes owned by the Swift caller.
        // The caller guarantees the pointer is valid for the duration of this call.
        let bytes = unsafe { slice::from_raw_parts(data, len) };
        match init_backend(bytes) {
            Ok(backend) => Box::into_raw(Box::new(backend)) as *mut c_void,
            Err(_) => std::ptr::null_mut(),
        }
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Execute a protobuf service method.
///
/// On success, is_error is set to false and the returned ByteBuffer contains
/// the serialized protobuf response. On error, is_error is set to true and
/// the returned ByteBuffer contains a serialized BackendError message.
///
/// The returned ByteBuffer must be freed with anki_free_buffer().
#[unsafe(no_mangle)]
pub extern "C" fn anki_command(
    backend: *mut c_void,
    service: u32,
    method: u32,
    input: *const u8,
    input_len: usize,
    is_error: *mut bool,
) -> ByteBuffer {
    let result = ffi_common::catch_ffi_panic_unwind_safe(|| {
        // SAFETY: `backend` was created by `anki_init` via `Box::into_raw` and has not been freed.
        // The caller guarantees exclusive access (no concurrent mutation).
        let backend = unsafe { &*(backend as *const Backend) };
        // SAFETY: `input` points to `input_len` bytes owned by the Swift caller.
        // The caller guarantees the pointer is valid for the duration of this call.
        let input_bytes = unsafe { slice::from_raw_parts(input, input_len) };
        match backend.run_service_method(service, method, input_bytes) {
            Ok(response) => {
                // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
                unsafe { *is_error = false };
                ByteBuffer::from_vec(response)
            }
            Err(err_bytes) => {
                // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
                unsafe { *is_error = true };
                ByteBuffer::from_vec(err_bytes)
            }
        }
    });
    match result {
        Ok(buf) => buf,
        Err(ffi_err) => {
            // SAFETY: `is_error` is a valid pointer provided by the Swift caller.
            unsafe { *is_error = true };
            ByteBuffer::from_str(&ffi_err.to_string())
        }
    }
}

/// Free a Backend instance created by anki_init.
#[unsafe(no_mangle)]
pub extern "C" fn anki_free(backend: *mut c_void) {
    let _ = ffi_common::catch_ffi_panic_unwind_safe(|| {
        if !backend.is_null() {
            // SAFETY: `backend` was created by `anki_init` via `Box::into_raw`.
            // The caller guarantees this is the final use of this pointer.
            unsafe { drop(Box::from_raw(backend as *mut Backend)) };
        }
    });
}

/// Free a ByteBuffer returned by anki_command.
#[unsafe(no_mangle)]
pub extern "C" fn anki_free_buffer(buf: ByteBuffer) {
    let _ = ffi_common::catch_ffi_panic_unwind_safe(|| {
        // SAFETY: `buf` was produced by `ByteBuffer::from_vec`.
        // The caller guarantees this buffer has not already been freed.
        unsafe { buf.free() };
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_with_invalid_protobuf_returns_null() {
        let garbage = [0xFF, 0xFE, 0xFD];
        let ptr = anki_init(garbage.as_ptr(), garbage.len());
        assert!(ptr.is_null());
    }

    #[test]
    fn free_null_does_not_crash() {
        anki_free(std::ptr::null_mut());
    }

    #[test]
    fn free_buffer_null_data_does_not_crash() {
        anki_free_buffer(ByteBuffer::empty());
    }

    #[test]
    fn free_buffer_valid_data_does_not_crash() {
        anki_free_buffer(ByteBuffer::from_vec(vec![1u8, 2, 3]));
    }

    #[test]
    fn byte_buffer_from_vec_roundtrip() {
        let buf = ByteBuffer::from_vec(vec![10u8, 20, 30, 40]);
        assert_eq!(buf.len, 4);
        assert!(!buf.data.is_null());
        anki_free_buffer(buf);
    }
}
