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
