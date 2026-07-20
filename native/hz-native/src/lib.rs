mod error;
mod ffi;
pub mod huffman;

pub use ffi::{
    hz_native_abi_version, hz_native_compress, hz_native_compress_file, hz_native_decompress,
    hz_native_decompress_file, hz_native_is_available, hz_native_result_free,
    hz_native_version_string,
};
