use crate::error::NativeError;

use super::stream::compress_to_vec;

pub fn compress(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    compress_to_vec(input)
}
