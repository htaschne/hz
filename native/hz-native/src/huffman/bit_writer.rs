use crate::error::NativeError;

use super::codes::HuffmanCode;

#[derive(Debug, Default)]
pub struct BitWriter {
    bytes: Vec<u8>,
    current_byte: u8,
    bit_index: u8,
    bit_count: u64,
}

impl BitWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn write_bit(&mut self, bit: bool) -> Result<(), NativeError> {
        if bit {
            self.current_byte |= 1 << (7 - self.bit_index);
        }

        self.bit_index += 1;
        self.bit_count = self
            .bit_count
            .checked_add(1)
            .ok_or(NativeError::Internal("encoded bit count overflowed"))?;

        if self.bit_index == 8 {
            self.bytes.push(self.current_byte);
            self.current_byte = 0;
            self.bit_index = 0;
        }

        Ok(())
    }

    pub fn write_code(&mut self, code: &HuffmanCode) -> Result<(), NativeError> {
        for &bit in code.bits() {
            self.write_bit(bit)?;
        }

        Ok(())
    }

    pub fn finish(mut self) -> EncodedBits {
        if self.bit_index > 0 {
            self.bytes.push(self.current_byte);
            self.current_byte = 0;
            self.bit_index = 0;
        }

        EncodedBits {
            bytes: self.bytes,
            bit_count: self.bit_count,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EncodedBits {
    pub bytes: Vec<u8>,
    pub bit_count: u64,
}

pub fn encode_payload(
    input: &[u8],
    codes: &[Option<HuffmanCode>],
) -> Result<EncodedBits, NativeError> {
    let mut writer = BitWriter::new();

    for &byte in input {
        let code = codes
            .get(usize::from(byte))
            .and_then(Option::as_ref)
            .ok_or(NativeError::Internal("missing Huffman code for input byte"))?;
        writer.write_code(code)?;
    }

    Ok(writer.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::huffman::codes::make_tree_code_table;
    use crate::huffman::codes::HuffmanCode;
    use crate::huffman::frequency::byte_frequencies;
    use crate::huffman::tree::build_huffman_tree;

    fn code(bits: &[bool]) -> HuffmanCode {
        HuffmanCode::new(bits.to_vec()).expect("valid code")
    }

    #[test]
    fn empty_payload_has_zero_bits_and_no_bytes() {
        let encoded = encode_payload(&[], &vec![None; 256]).expect("empty payload");

        assert_eq!(
            encoded,
            EncodedBits {
                bytes: vec![],
                bit_count: 0
            }
        );
    }

    #[test]
    fn writes_known_partial_byte_pattern() {
        let mut writer = BitWriter::new();
        writer
            .write_code(&code(&[true, false, true]))
            .expect("write");
        let encoded = writer.finish();

        assert_eq!(encoded.bytes, vec![0b1010_0000]);
        assert_eq!(encoded.bit_count, 3);
    }

    #[test]
    fn writes_exact_byte_boundary() {
        let mut writer = BitWriter::new();
        writer
            .write_code(&code(&[true, false, true, false, true, false, true, false]))
            .expect("write");
        let encoded = writer.finish();

        assert_eq!(encoded.bytes, vec![0b1010_1010]);
        assert_eq!(encoded.bit_count, 8);
    }

    #[test]
    fn writes_across_byte_boundary() {
        let mut writer = BitWriter::new();
        writer
            .write_code(&code(&[
                true, true, true, true, false, false, false, false, true,
            ]))
            .expect("write");
        let encoded = writer.finish();

        assert_eq!(encoded.bytes, vec![0b1111_0000, 0b1000_0000]);
        assert_eq!(encoded.bit_count, 9);
    }

    #[test]
    fn single_symbol_uses_zero_bits_like_swift() {
        let frequencies = byte_frequencies(b"aaaa");
        let tree = build_huffman_tree(&frequencies).expect("tree");
        let table = make_tree_code_table(&tree).expect("table");
        let encoded = encode_payload(b"aaaa", &table).expect("payload");

        assert_eq!(encoded.bytes, vec![0]);
        assert_eq!(encoded.bit_count, 4);
    }

    #[test]
    fn all_byte_values_can_be_encoded() {
        let input: Vec<u8> = (0..=255).collect();
        let frequencies = byte_frequencies(&input);
        let tree = build_huffman_tree(&frequencies).expect("tree");
        let table = make_tree_code_table(&tree).expect("table");
        let encoded = encode_payload(&input, &table).expect("payload");

        assert_eq!(encoded.bit_count, 2_048);
        assert_eq!(encoded.bytes.len(), 256);
    }
}
