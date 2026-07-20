use crate::error::NativeError;

use super::stream::decompress_to_vec;

pub fn decompress(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    decompress_to_vec(input)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::huffman::compress;

    fn round_trip(input: &[u8]) {
        let archive = compress(input).expect("compress");
        let decoded = decompress(&archive).expect("decompress");
        assert_eq!(decoded, input);
    }

    #[test]
    fn round_trips_text() {
        round_trip(b"the quick brown fox jumps over the lazy dog");
    }

    #[test]
    fn round_trips_empty_input() {
        round_trip(b"");
    }

    #[test]
    fn round_trips_single_repeated_byte() {
        round_trip(b"aaaaaaaaaaaaaaaa");
    }

    #[test]
    fn round_trips_binary_zero_bytes() {
        round_trip(&[0, 1, 0, 2, 0, 3, 255, 0]);
    }

    #[test]
    fn padding_bits_do_not_create_extra_output() {
        let archive = compress(b"abc").expect("compress");
        let decoded = decompress(&archive).expect("decompress");

        assert_eq!(decoded, b"abc");
    }
}
