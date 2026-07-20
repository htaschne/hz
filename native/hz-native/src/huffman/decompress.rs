use crate::error::NativeError;

use super::archive::HzArchive;
use super::bit_reader::BitReader;
use super::tree::build_huffman_tree;
use super::tree::HuffmanTree;

pub fn decompress(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    let archive = HzArchive::parse(input)?;
    decode_archive(&archive)
}

fn decode_archive(archive: &HzArchive) -> Result<Vec<u8>, NativeError> {
    if archive.original_byte_count() == 0 {
        return Ok(Vec::new());
    }

    let tree = build_huffman_tree(archive.frequencies())
        .ok_or(NativeError::InvalidArgument("missing Huffman tree"))?;

    if let Some(byte) = tree.leaf_byte() {
        return decode_single_symbol_archive(byte, archive);
    }

    let capacity = usize::try_from(archive.original_byte_count())
        .map_err(|_| NativeError::InvalidArgument("decoded output is too large"))?;
    let mut output = Vec::with_capacity(capacity);
    let mut reader = BitReader::new(archive.payload(), archive.encoded_bit_count());
    let mut node = &tree;

    for _ in 0..archive.encoded_bit_count() {
        let bit = reader.read_bit()?;
        node = next_node(node, bit)?;

        if let Some(byte) = node.leaf_byte() {
            output.push(byte);
            if output.len() as u64 > archive.original_byte_count() {
                return Err(NativeError::InvalidArgument("invalid Huffman bitstream"));
            }

            if output.len() as u64 == archive.original_byte_count() {
                return Ok(output);
            }

            node = &tree;
        }
    }

    if output.len() as u64 == archive.original_byte_count() {
        Ok(output)
    } else {
        Err(NativeError::InvalidArgument("invalid Huffman bitstream"))
    }
}

fn next_node(tree: &HuffmanTree, bit: bool) -> Result<&HuffmanTree, NativeError> {
    let child = if bit { tree.right() } else { tree.left() };
    child.ok_or(NativeError::InvalidArgument("invalid Huffman bitstream"))
}

fn decode_single_symbol_archive(byte: u8, archive: &HzArchive) -> Result<Vec<u8>, NativeError> {
    if archive.encoded_bit_count() != archive.original_byte_count() {
        return Err(NativeError::InvalidArgument(
            "invalid single-symbol Huffman bitstream",
        ));
    }

    let mut reader = BitReader::new(archive.payload(), archive.encoded_bit_count());
    for _ in 0..archive.encoded_bit_count() {
        if reader.read_bit()? {
            return Err(NativeError::InvalidArgument(
                "invalid single-symbol Huffman bitstream",
            ));
        }
    }

    let count = usize::try_from(archive.original_byte_count())
        .map_err(|_| NativeError::InvalidArgument("decoded output is too large"))?;
    Ok(vec![byte; count])
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
