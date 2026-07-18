use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::error::NativeError;
use crate::huffman;

const ABI_VERSION: u32 = 1;
const VERSION_STRING: *const c_char = c"hz-native 0.1.0".as_ptr();

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HzNativeStatus {
    Ok = 0,
    NotImplemented = 1,
    InvalidArgument = 2,
    AllocationFailed = 3,
    InternalError = 4,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct HzNativeBuffer {
    pub data: *mut u8,
    pub length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct HzNativeResult {
    pub status: HzNativeStatus,
    pub buffer: HzNativeBuffer,
    pub error_message: *const c_char,
}

impl HzNativeResult {
    fn ok(bytes: Vec<u8>) -> Self {
        let mut boxed = bytes.into_boxed_slice();
        let result = Self {
            status: HzNativeStatus::Ok,
            buffer: HzNativeBuffer {
                data: boxed.as_mut_ptr(),
                length: boxed.len(),
            },
            error_message: ptr::null(),
        };
        std::mem::forget(boxed);
        result
    }

    fn error(error: NativeError) -> Self {
        Self {
            status: error.status(),
            buffer: HzNativeBuffer {
                data: ptr::null_mut(),
                length: 0,
            },
            error_message: error.message(),
        }
    }
}

#[no_mangle]
pub extern "C" fn hz_native_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn hz_native_version_string() -> *const c_char {
    VERSION_STRING
}

#[no_mangle]
pub extern "C" fn hz_native_is_available() -> bool {
    true
}

#[no_mangle]
pub extern "C" fn hz_native_compress(input: *const u8, input_length: usize) -> HzNativeResult {
    ffi_result_from(input, input_length, huffman::compress)
}

#[no_mangle]
pub extern "C" fn hz_native_decompress(input: *const u8, input_length: usize) -> HzNativeResult {
    ffi_result_from(input, input_length, huffman::decompress)
}

#[no_mangle]
pub extern "C" fn hz_native_result_free(result: HzNativeResult) {
    if result.buffer.data.is_null() || result.buffer.length == 0 {
        return;
    }

    let slice_pointer = ptr::slice_from_raw_parts_mut(result.buffer.data, result.buffer.length);
    unsafe {
        drop(Box::from_raw(slice_pointer));
    }
}

fn ffi_result_from(
    input: *const u8,
    input_length: usize,
    operation: fn(&[u8]) -> Result<Vec<u8>, NativeError>,
) -> HzNativeResult {
    match catch_unwind(AssertUnwindSafe(|| {
        let input = input_slice(input, input_length).map_err(HzNativeResult::error)?;
        operation(input)
            .map(HzNativeResult::ok)
            .map_err(HzNativeResult::error)
    })) {
        Ok(Ok(result)) => result,
        Ok(Err(error_result)) => error_result,
        Err(_) => HzNativeResult::error(NativeError::Internal(
            "Rust native engine panicked across FFI boundary",
        )),
    }
}

fn input_slice<'a>(input: *const u8, input_length: usize) -> Result<&'a [u8], NativeError> {
    if input.is_null() {
        return if input_length == 0 {
            Ok(&[])
        } else {
            Err(NativeError::InvalidArgument(
                "input pointer is null but input length is nonzero",
            ))
        };
    }

    Ok(unsafe { slice::from_raw_parts(input, input_length) })
}

#[cfg(test)]
mod tests {
    use std::ffi::CStr;
    use std::ptr;

    use super::*;

    #[test]
    fn abi_version_is_nonzero() {
        assert!(hz_native_abi_version() > 0);
    }

    #[test]
    fn version_string_is_valid_c_text() {
        let pointer = hz_native_version_string();
        assert!(!pointer.is_null());

        let version = unsafe { CStr::from_ptr(pointer) };
        assert!(version.to_str().is_ok());
        assert!(!version.to_bytes().is_empty());
    }

    #[test]
    fn availability_returns_true() {
        assert!(hz_native_is_available());
    }

    #[test]
    fn compression_returns_not_implemented() {
        let input = [1_u8, 2, 3];
        let result = hz_native_compress(input.as_ptr(), input.len());
        assert_eq!(result.status, HzNativeStatus::NotImplemented);
        assert!(!result.error_message.is_null());
        hz_native_result_free(result);
    }

    #[test]
    fn decompression_returns_not_implemented() {
        let input = [1_u8, 2, 3];
        let result = hz_native_decompress(input.as_ptr(), input.len());
        assert_eq!(result.status, HzNativeStatus::NotImplemented);
        assert!(!result.error_message.is_null());
        hz_native_result_free(result);
    }

    #[test]
    fn empty_input_is_safe() {
        let result = hz_native_compress(ptr::null(), 0);
        assert_eq!(result.status, HzNativeStatus::NotImplemented);
        hz_native_result_free(result);
    }

    #[test]
    fn null_input_with_nonzero_length_is_invalid_argument() {
        let result = hz_native_compress(ptr::null(), 1);
        assert_eq!(result.status, HzNativeStatus::InvalidArgument);
        hz_native_result_free(result);
    }

    #[test]
    fn result_free_handles_zero_value_result() {
        hz_native_result_free(HzNativeResult {
            status: HzNativeStatus::Ok,
            buffer: HzNativeBuffer {
                data: ptr::null_mut(),
                length: 0,
            },
            error_message: ptr::null(),
        });
    }

    #[test]
    fn ffi_boundary_converts_panics_to_internal_errors() {
        fn panicking_operation(_: &[u8]) -> Result<Vec<u8>, NativeError> {
            panic!("test panic");
        }

        let result = ffi_result_from(ptr::null(), 0, panicking_operation);
        assert_eq!(result.status, HzNativeStatus::InternalError);
        hz_native_result_free(result);
    }
}
