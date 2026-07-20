use std::os::raw::c_char;

use crate::ffi::HzNativeStatus;

#[derive(Debug, Eq, PartialEq)]
pub enum NativeError {
    InvalidArgument(&'static str),
    #[allow(dead_code)]
    AllocationFailed(&'static str),
    Internal(&'static str),
}

impl NativeError {
    pub fn status(&self) -> HzNativeStatus {
        match self {
            Self::InvalidArgument(_) => HzNativeStatus::InvalidArgument,
            Self::AllocationFailed(_) => HzNativeStatus::AllocationFailed,
            Self::Internal(_) => HzNativeStatus::InternalError,
        }
    }

    pub fn message(&self) -> *const c_char {
        match self {
            Self::InvalidArgument(message)
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
        "decoded output is too large" => c"decoded output is too large".as_ptr(),
        "duplicate Hz frequency table entry" => c"duplicate Hz frequency table entry".as_ptr(),
        "empty archive metadata is inconsistent" => {
            c"empty archive metadata is inconsistent".as_ptr()
        }
        "frequency table has too many entries" => c"frequency table has too many entries".as_ptr(),
        "frequency total does not match input length" => {
            c"frequency total does not match input length".as_ptr()
        }
        "Huffman bitstream is too large" => c"Huffman bitstream is too large".as_ptr(),
        "Hz frequency total does not match original byte count" => {
            c"Hz frequency total does not match original byte count".as_ptr()
        }
        "Hz frequency total overflowed" => c"Hz frequency total overflowed".as_ptr(),
        "Hz payload length does not match encoded bit count" => {
            c"Hz payload length does not match encoded bit count".as_ptr()
        }
        "invalid encoded bit count in Hz archive" => {
            c"invalid encoded bit count in Hz archive".as_ptr()
        }
        "invalid Huffman bitstream" => c"invalid Huffman bitstream".as_ptr(),
        "invalid Hz frequency table" => c"invalid Hz frequency table".as_ptr(),
        "invalid recursive layer count in Hz archive" => {
            c"invalid recursive layer count in Hz archive".as_ptr()
        }
        "invalid single-symbol Huffman bitstream" => {
            c"invalid single-symbol Huffman bitstream".as_ptr()
        }
        "missing Huffman code for input byte" => c"missing Huffman code for input byte".as_ptr(),
        "missing Huffman tree" => c"missing Huffman tree".as_ptr(),
        "non-empty archive has no encoded payload" => {
            c"non-empty archive has no encoded payload".as_ptr()
        }
        "read past end of Huffman bitstream" => c"read past end of Huffman bitstream".as_ptr(),
        "truncated Hz archive header" => c"truncated Hz archive header".as_ptr(),
        "unsupported Hz archive flags" => c"unsupported Hz archive flags".as_ptr(),
        "unsupported Hz archive version" => c"unsupported Hz archive version".as_ptr(),
        "unsupported legacy or invalid Hz archive" => {
            c"unsupported legacy or invalid Hz archive".as_ptr()
        }
        _ => c"unknown Rust native engine error".as_ptr(),
    }
}
