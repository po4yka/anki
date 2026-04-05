use std::ffi::{CStr, c_char, c_void};
use std::slice;

use tokio::runtime::Runtime;

/// Byte buffer for transferring owned data across the FFI boundary.
/// Swift must call atlas_free_buffer() when it is done with the data.
#[repr(C)]
pub struct AtlasByteBuffer {
    data: *mut u8,
    len: usize,
}

impl AtlasByteBuffer {
    fn from_vec(v: Vec<u8>) -> Self {
        let mut v = v.into_boxed_slice();
        let buf = AtlasByteBuffer {
            data: v.as_mut_ptr(),
            len: v.len(),
        };
        std::mem::forget(v);
        buf
    }

    fn from_str(s: &str) -> Self {
        Self::from_vec(s.as_bytes().to_vec())
    }

    fn empty() -> Self {
        AtlasByteBuffer {
            data: std::ptr::null_mut(),
            len: 0,
        }
    }
}

/// Opaque handle holding a tokio Runtime.
/// SurfaceServices wiring will be added when infrastructure (PgPool, Qdrant) is set up.
pub struct AtlasHandle {
    runtime: Runtime,
}

/// Initialize an Atlas handle from a JSON-encoded AtlasConfig.
///
/// Returns an opaque pointer on success. The caller must pass this pointer to
/// all subsequent atlas_command calls and must call atlas_free() when done.
/// Returns null on error.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_init(
    _config_data: *const u8,
    _config_len: usize,
) -> *mut c_void {
    match Runtime::new() {
        Ok(runtime) => {
            let handle = Box::new(AtlasHandle { runtime });
            Box::into_raw(handle) as *mut c_void
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Dispatch a JSON method call to Atlas services.
///
/// On success, is_error is set to false and the returned AtlasByteBuffer contains
/// the JSON-encoded response. On error, is_error is set to true and the returned
/// AtlasByteBuffer contains an error message string.
///
/// The returned AtlasByteBuffer must be freed with atlas_free_buffer().
#[unsafe(no_mangle)]
pub extern "C" fn atlas_command(
    _handle: *mut c_void,
    method: *const c_char,
    _input: *const u8,
    _input_len: usize,
    is_error: *mut bool,
) -> AtlasByteBuffer {
    let method_str = unsafe {
        match CStr::from_ptr(method).to_str() {
            Ok(s) => s,
            Err(_) => {
                *is_error = true;
                return AtlasByteBuffer::from_str("invalid UTF-8 in method name");
            }
        }
    };

    let error_msg: &str = match method_str {
        "search" => "Atlas search not yet configured",
        "search_chunks" => "Atlas chunk search not yet configured",
        "get_taxonomy_tree" => "Atlas analytics not yet configured",
        "get_coverage" => "Atlas analytics not yet configured",
        "get_gaps" => "Atlas analytics not yet configured",
        "get_weak_notes" => "Atlas analytics not yet configured",
        "find_duplicates" => "Atlas analytics not yet configured",
        "generate_preview" => "Atlas generator not yet configured",
        "obsidian_scan" => "Atlas obsidian not yet configured",
        "kg_see_also" => "Atlas knowledge graph not yet configured",
        _ => "Unknown atlas method",
    };

    unsafe { *is_error = true };
    AtlasByteBuffer::from_str(error_msg)
}

/// Free an AtlasHandle instance created by atlas_init.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_free(handle: *mut c_void) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle as *mut AtlasHandle)) };
    }
}

/// Free an AtlasByteBuffer returned by atlas_command.
#[unsafe(no_mangle)]
pub extern "C" fn atlas_free_buffer(buf: AtlasByteBuffer) {
    if !buf.data.is_null() {
        unsafe {
            drop(Box::from_raw(slice::from_raw_parts_mut(buf.data, buf.len)));
        };
    }
}
