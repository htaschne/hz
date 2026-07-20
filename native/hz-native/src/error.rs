use std::os::raw::c_char;

use crate::ffi::HzNativeStatus;

#[derive(Debug, Eq, PartialEq)]
pub enum NativeError {
    NotImplemented(&'static str),
    InvalidArgument(&'static str),
    #[allow(dead_code)]
    AllocationFailed(&'static str),
    Internal(&'static str),
}

impl NativeError {
    pub fn status(&self) -> HzNativeStatus {
        match self {
            Self::NotImplemented(_) => HzNativeStatus::NotImplemented,
            Self::InvalidArgument(_) => HzNativeStatus::InvalidArgument,
            Self::AllocationFailed(_) => HzNativeStatus::AllocationFailed,
            Self::Internal(_) => HzNativeStatus::InternalError,
        }
    }

    pub fn message(&self) -> *const c_char {
        match self {
            Self::NotImplemented(message)
            | Self::InvalidArgument(message)
            | Self::AllocationFailed(message)
            | Self::Internal(message) => static_c_message(message),
        }
    }
}

pub fn static_c_message(message: &'static str) -> *const c_char {
    match message {
        "Rust Huffman compression is not implemented yet" => {
            c"Rust Huffman compression is not implemented yet".as_ptr()
        }
        "Rust Huffman decompression is not implemented yet" => {
            c"Rust Huffman decompression is not implemented yet".as_ptr()
        }
        "input pointer is null but input length is nonzero" => {
            c"input pointer is null but input length is nonzero".as_ptr()
        }
        "Rust native engine panicked across FFI boundary" => {
            c"Rust native engine panicked across FFI boundary".as_ptr()
        }
        "Rust native engine allocation failed" => c"Rust native engine allocation failed".as_ptr(),
        "Huffman code must contain at least one bit" => {
            c"Huffman code must contain at least one bit".as_ptr()
        }
        "Huffman code length cannot be zero" => c"Huffman code length cannot be zero".as_ptr(),
        "canonical code lengths are not sorted" => {
            c"canonical code lengths are not sorted".as_ptr()
        }
        "canonical Huffman code space overflowed" => {
            c"canonical Huffman code space overflowed".as_ptr()
        }
        "encoded bit count overflowed" => c"encoded bit count overflowed".as_ptr(),
        "encoded payload is too large" => c"encoded payload is too large".as_ptr(),
        "encoded payload length does not match bit count" => {
            c"encoded payload length does not match bit count".as_ptr()
        }
        "empty archive metadata is inconsistent" => {
            c"empty archive metadata is inconsistent".as_ptr()
        }
        "frequency table has too many entries" => c"frequency table has too many entries".as_ptr(),
        "frequency total does not match input length" => {
            c"frequency total does not match input length".as_ptr()
        }
        "missing Huffman code for input byte" => c"missing Huffman code for input byte".as_ptr(),
        "non-empty archive has no encoded payload" => {
            c"non-empty archive has no encoded payload".as_ptr()
        }
        _ => c"unknown Rust native engine error".as_ptr(),
    }
}
