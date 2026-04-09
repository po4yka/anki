#![allow(unsafe_code)]

use std::panic::{AssertUnwindSafe, catch_unwind};

/// Byte buffer for transferring owned data across the FFI boundary.
/// The caller must free the buffer using the appropriate free function.
#[repr(C)]
pub struct ByteBuffer {
    pub data: *mut u8,
    pub len: usize,
}

impl ByteBuffer {
    pub fn from_vec(v: Vec<u8>) -> Self {
        let mut v = v.into_boxed_slice();
        let buf = ByteBuffer {
            data: v.as_mut_ptr(),
            len: v.len(),
        };
        std::mem::forget(v);
        buf
    }

    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Self {
        Self::from_vec(s.as_bytes().to_vec())
    }

    pub fn empty() -> Self {
        ByteBuffer {
            data: std::ptr::null_mut(),
            len: 0,
        }
    }

    /// Free this buffer. Safe to call on null/empty buffers.
    /// # Safety
    /// The buffer must have been created by `from_vec` or `from_str` and not already freed.
    pub unsafe fn free(self) {
        if !self.data.is_null() {
            // SAFETY: `self.data` and `self.len` were produced by `from_vec`.
            // The caller guarantees this buffer has not already been freed.
            unsafe {
                drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                    self.data, self.len,
                )));
            }
        }
    }
}

/// Structured error type for FFI boundary errors.
#[derive(Debug)]
pub enum FfiError {
    /// A Rust panic was caught during execution.
    PanicCaught(String),
    /// Invalid input data provided by the caller.
    BadInput(String),
    /// The handle has not been initialized.
    NotInitialized,
}

impl std::fmt::Display for FfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::PanicCaught(msg) => write!(f, "internal panic: {msg}"),
            Self::BadInput(msg) => write!(f, "bad input: {msg}"),
            Self::NotInitialized => write!(f, "not initialized"),
        }
    }
}

impl std::error::Error for FfiError {}

/// Execute a closure, catching any panics and converting them to `FfiError`.
pub fn catch_ffi_panic<F, T>(f: F) -> Result<T, FfiError>
where
    F: FnOnce() -> T + std::panic::UnwindSafe,
{
    catch_unwind(f).map_err(|panic| {
        let msg = panic
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| panic.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "unknown panic".to_string());
        FfiError::PanicCaught(msg)
    })
}

/// Like `catch_ffi_panic` but wraps a non-UnwindSafe closure with AssertUnwindSafe.
pub fn catch_ffi_panic_unwind_safe<F, T>(f: F) -> Result<T, FfiError>
where
    F: FnOnce() -> T,
{
    catch_ffi_panic(AssertUnwindSafe(f))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_buffer_from_vec_roundtrip() {
        let buf = ByteBuffer::from_vec(vec![1u8, 2, 3]);
        assert_eq!(buf.len, 3);
        assert!(!buf.data.is_null());
        unsafe { buf.free() };
    }

    #[test]
    fn byte_buffer_from_str() {
        let buf = ByteBuffer::from_str("hello");
        assert_eq!(buf.len, 5);
        unsafe { buf.free() };
    }

    #[test]
    fn byte_buffer_empty() {
        let buf = ByteBuffer::empty();
        assert!(buf.data.is_null());
        assert_eq!(buf.len, 0);
        unsafe { buf.free() };
    }

    #[test]
    fn catch_ffi_panic_success() {
        let result = catch_ffi_panic(|| 42);
        assert_eq!(result.unwrap(), 42);
    }

    #[test]
    fn catch_ffi_panic_catches_str_panic() {
        let result = catch_ffi_panic(|| panic!("test panic"));
        let err = result.unwrap_err();
        assert!(matches!(err, FfiError::PanicCaught(_)));
        assert!(err.to_string().contains("test panic"));
    }

    #[test]
    fn catch_ffi_panic_unwind_safe_works() {
        let mut x = 0;
        let result = catch_ffi_panic_unwind_safe(|| {
            x += 1;
            x
        });
        assert_eq!(result.unwrap(), 1);
    }
}
