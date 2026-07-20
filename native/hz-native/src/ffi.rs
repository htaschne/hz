use std::ffi::CStr;
use std::ffi::CString;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
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
        let error_message = CString::new(error.message_text())
            .unwrap_or_else(|_| CString::new("Rust native engine returned invalid error text").unwrap())
            .into_raw();

        Self {
            status: error.status(),
            buffer: HzNativeBuffer {
                data: ptr::null_mut(),
                length: 0,
            },
            error_message,
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
pub extern "C" fn hz_native_compress_file(
    source_path: *const c_char,
    destination_path: *const c_char,
) -> HzNativeResult {
    ffi_path_result_from(source_path, destination_path, |source, destination| {
        huffman::compress_file(source, destination)
    })
}

#[no_mangle]
pub extern "C" fn hz_native_decompress_file(
    source_path: *const c_char,
    destination_path: *const c_char,
) -> HzNativeResult {
    ffi_path_result_from(source_path, destination_path, |source, destination| {
        huffman::decompress_file(source, destination)
    })
}

#[no_mangle]
pub extern "C" fn hz_native_result_free(result: HzNativeResult) {
    if !result.error_message.is_null() {
        unsafe {
            drop(CString::from_raw(result.error_message.cast_mut()));
        }
    }

    if !result.buffer.data.is_null() && result.buffer.length > 0 {
        let slice_pointer = ptr::slice_from_raw_parts_mut(result.buffer.data, result.buffer.length);
        unsafe {
            drop(Box::from_raw(slice_pointer));
        }
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

fn ffi_path_result_from<T>(
    source_path: *const c_char,
    destination_path: *const c_char,
    operation: impl FnOnce(&Path, &Path) -> Result<T, NativeError>,
) -> HzNativeResult {
    match catch_unwind(AssertUnwindSafe(|| {
        let source_path = path_from_c_string(source_path).map_err(HzNativeResult::error)?;
        let destination_path =
            path_from_c_string(destination_path).map_err(HzNativeResult::error)?;
        operation(Path::new(source_path), Path::new(destination_path))
            .map(|_| HzNativeResult::ok(Vec::new()))
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

fn path_from_c_string<'a>(path: *const c_char) -> Result<&'a str, NativeError> {
    if path.is_null() {
        return Err(NativeError::InvalidArgument("path pointer is null"));
    }

    unsafe { CStr::from_ptr(path) }
        .to_str()
        .map_err(|_| NativeError::InvalidArgument("path must be valid UTF-8"))
}

#[cfg(test)]
mod tests {
    use std::ffi::CStr;
    use std::ffi::CString;
    use std::fs;
    use std::ptr;
    use std::slice;
    use std::time::SystemTime;
    use std::time::UNIX_EPOCH;

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
    fn compression_returns_archive_buffer() {
        let input = [1_u8, 2, 3];
        let result = hz_native_compress(input.as_ptr(), input.len());
        assert_eq!(result.status, HzNativeStatus::Ok);
        assert!(result.error_message.is_null());
        assert!(!result.buffer.data.is_null());
        assert!(result.buffer.length > 26);

        let bytes = unsafe { slice::from_raw_parts(result.buffer.data, result.buffer.length) };
        assert_eq!(&bytes[0..4], b"HZF1");
        hz_native_result_free(result);
    }

    #[test]
    fn decompression_returns_original_input() {
        let input = [1_u8, 2, 3];
        let archive = hz_native_compress(input.as_ptr(), input.len());
        assert_eq!(archive.status, HzNativeStatus::Ok);

        let result = hz_native_decompress(archive.buffer.data, archive.buffer.length);
        assert_eq!(result.status, HzNativeStatus::Ok);
        assert!(result.error_message.is_null());
        assert_eq!(result.buffer.length, input.len());

        let bytes = unsafe { slice::from_raw_parts(result.buffer.data, result.buffer.length) };
        assert_eq!(bytes, input);

        hz_native_result_free(result);
        hz_native_result_free(archive);
    }

    #[test]
    fn empty_input_is_safe() {
        let result = hz_native_compress(ptr::null(), 0);
        assert_eq!(result.status, HzNativeStatus::Ok);
        assert_eq!(result.buffer.length, 26);
        hz_native_result_free(result);
    }

    #[test]
    fn null_input_with_nonzero_length_is_invalid_argument() {
        let result = hz_native_compress(ptr::null(), 1);
        assert_eq!(result.status, HzNativeStatus::InvalidArgument);
        hz_native_result_free(result);
    }

    #[test]
    fn file_compression_round_trips_through_streaming_ffi() {
        let directory = unique_temp_directory();
        fs::create_dir_all(&directory).expect("temp dir");
        let source = directory.join("input.bin");
        let archive = directory.join("input.hz");
        let output = directory.join("output.bin");
        let original = b"file ffi banana banana";
        fs::write(&source, original).expect("write source");

        let source_c = CString::new(source.to_string_lossy().as_bytes()).expect("source c string");
        let archive_c =
            CString::new(archive.to_string_lossy().as_bytes()).expect("archive c string");
        let output_c = CString::new(output.to_string_lossy().as_bytes()).expect("output c string");

        let compressed = hz_native_compress_file(source_c.as_ptr(), archive_c.as_ptr());
        assert_eq!(compressed.status, HzNativeStatus::Ok);
        hz_native_result_free(compressed);
        assert!(archive.exists());

        let decompressed = hz_native_decompress_file(archive_c.as_ptr(), output_c.as_ptr());
        assert_eq!(decompressed.status, HzNativeStatus::Ok);
        hz_native_result_free(decompressed);

        assert_eq!(fs::read(output).expect("read output"), original);
        let _ = fs::remove_dir_all(directory);
    }

    #[test]
    fn file_compression_rejects_null_path() {
        let result = hz_native_compress_file(ptr::null(), ptr::null());

        assert_eq!(result.status, HzNativeStatus::InvalidArgument);
        hz_native_result_free(result);
    }

    #[test]
    fn file_compression_reports_temporary_creation_context() {
        let directory = unique_temp_directory();
        fs::create_dir_all(&directory).expect("temp dir");
        let source = directory.join("input.bin");
        let archive = directory.join("missing-parent").join("input.hz");
        fs::write(&source, b"diagnostic source").expect("write source");

        let source_c = CString::new(source.to_string_lossy().as_bytes()).expect("source c string");
        let archive_c =
            CString::new(archive.to_string_lossy().as_bytes()).expect("archive c string");

        let result = hz_native_compress_file(source_c.as_ptr(), archive_c.as_ptr());
        assert_eq!(result.status, HzNativeStatus::InternalError);
        assert!(!result.error_message.is_null());

        let message = unsafe { CStr::from_ptr(result.error_message) }
            .to_str()
            .expect("error message utf8");
        assert!(message.contains("failed to create temporary destination file"));
        assert!(message.contains("kind="));
        assert!(message.contains("os_error="));

        hz_native_result_free(result);
        let _ = fs::remove_dir_all(directory);
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

    fn unique_temp_directory() -> std::path::PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!("hz-native-ffi-{unique}"))
    }
}
