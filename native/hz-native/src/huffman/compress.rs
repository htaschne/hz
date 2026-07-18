use crate::error::NativeError;

pub fn compress(_input: &[u8]) -> Result<Vec<u8>, NativeError> {
    // TODO(native-huffman): implement the future compression pipeline with
    // frequency table, tree construction, code generation, bit writer, archive
    // serialization, and recursive compression boundaries.
    Err(NativeError::NotImplemented(
        "Rust Huffman compression is not implemented yet",
    ))
}
