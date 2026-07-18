use crate::error::NativeError;

pub fn decompress(_input: &[u8]) -> Result<Vec<u8>, NativeError> {
    // TODO(native-huffman): implement the future decompression pipeline with
    // archive parsing, tree reconstruction, bit reader, payload decoding, and
    // recursive decompression boundaries.
    Err(NativeError::NotImplemented(
        "Rust Huffman decompression is not implemented yet",
    ))
}
