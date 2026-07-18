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
        _ => c"unknown Rust native engine error".as_ptr(),
    }
}
