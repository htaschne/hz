use crate::error::NativeError;

use super::frequency::total_frequency;
use super::frequency::FrequencyTable;

/// Version 2 `.hz` archive format.
///
/// Multi-byte integers are little-endian.
///
/// Header:
/// - 4 bytes: magic bytes, ASCII "HZF1"
/// - 1 byte: format version, currently 2
/// - 1 byte: flags, currently 0
/// - 2 bytes: recursive layer count
/// - 8 bytes: original uncompressed byte count
/// - 8 bytes: encoded payload bit count
/// - 2 bytes: frequency table entry count
/// - N entries:
///   - 1 byte: symbol
///   - 8 bytes: symbol frequency in the original input
/// - remaining bytes: Huffman encoded payload, padded with zero bits to the next byte
#[derive(Debug)]
pub struct HzArchive {
    recursive_layer_count: u16,
    original_byte_count: u64,
    encoded_bit_count: u64,
    frequencies: FrequencyTable,
    payload: Vec<u8>,
}

impl HzArchive {
    const MAGIC: [u8; 4] = *b"HZF1";
    const VERSION: u8 = 2;
    const FLAGS: u8 = 0;

    pub fn new(
        recursive_layer_count: u16,
        original_byte_count: u64,
        encoded_bit_count: u64,
        frequencies: FrequencyTable,
        payload: Vec<u8>,
    ) -> Result<Self, NativeError> {
        let frequency_total = total_frequency(&frequencies);
        if frequency_total != original_byte_count {
            return Err(NativeError::Internal(
                "frequency total does not match input length",
            ));
        }

        if original_byte_count == 0 {
            if frequency_total != 0 || encoded_bit_count != 0 || !payload.is_empty() {
                return Err(NativeError::Internal(
                    "empty archive metadata is inconsistent",
                ));
            }
        } else if encoded_bit_count == 0 || payload.is_empty() {
            return Err(NativeError::Internal(
                "non-empty archive has no encoded payload",
            ));
        }

        let expected_payload_len = expected_payload_length(encoded_bit_count)?;
        if payload.len() != expected_payload_len {
            return Err(NativeError::Internal(
                "encoded payload length does not match bit count",
            ));
        }

        Ok(Self {
            recursive_layer_count,
            original_byte_count,
            encoded_bit_count,
            frequencies,
            payload,
        })
    }

    pub fn serialize(&self) -> Result<Vec<u8>, NativeError> {
        let entry_count = self
            .frequencies
            .iter()
            .filter(|&&frequency| frequency > 0)
            .count();
        let entry_count = u16::try_from(entry_count)
            .map_err(|_| NativeError::Internal("frequency table has too many entries"))?;

        let mut output = Vec::with_capacity(26 + usize::from(entry_count) * 9 + self.payload.len());
        output.extend_from_slice(&Self::MAGIC);
        output.push(Self::VERSION);
        output.push(Self::FLAGS);
        output.extend_from_slice(&self.recursive_layer_count.to_le_bytes());
        output.extend_from_slice(&self.original_byte_count.to_le_bytes());
        output.extend_from_slice(&self.encoded_bit_count.to_le_bytes());
        output.extend_from_slice(&entry_count.to_le_bytes());

        for (byte, &frequency) in self.frequencies.iter().enumerate() {
            if frequency == 0 {
                continue;
            }

            output.push(byte as u8);
            output.extend_from_slice(&frequency.to_le_bytes());
        }

        output.extend_from_slice(&self.payload);
        Ok(output)
    }
}

fn expected_payload_length(encoded_bit_count: u64) -> Result<usize, NativeError> {
    let length = encoded_bit_count / 8 + u64::from(!encoded_bit_count.is_multiple_of(8));
    usize::try_from(length).map_err(|_| NativeError::Internal("encoded payload is too large"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::huffman::bit_writer::encode_payload;
    use crate::huffman::codes::make_tree_code_table;
    use crate::huffman::frequency::byte_frequencies;
    use crate::huffman::tree::build_huffman_tree;

    fn archive_for(input: &[u8]) -> HzArchive {
        let frequencies = byte_frequencies(input);
        let (payload, encoded_bit_count) = if let Some(tree) = build_huffman_tree(&frequencies) {
            let codes = make_tree_code_table(&tree).expect("code table");
            let encoded = encode_payload(input, &codes).expect("payload");
            (encoded.bytes, encoded.bit_count)
        } else {
            (Vec::new(), 0)
        };

        HzArchive::new(
            0,
            input.len() as u64,
            encoded_bit_count,
            frequencies,
            payload,
        )
        .expect("archive")
    }

    #[test]
    fn serializes_empty_archive_header() {
        let bytes = archive_for(&[]).serialize().expect("serialize");

        assert_eq!(
            bytes,
            vec![
                b'H', b'Z', b'F', b'1', 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0,
            ]
        );
    }

    #[test]
    fn serializes_frequency_entries_in_byte_order() {
        let bytes = archive_for(b"banana").serialize().expect("serialize");

        assert_eq!(&bytes[0..4], b"HZF1");
        assert_eq!(bytes[4], 2);
        assert_eq!(bytes[5], 0);
        assert_eq!(u16::from_le_bytes(bytes[6..8].try_into().unwrap()), 0);
        assert_eq!(u64::from_le_bytes(bytes[8..16].try_into().unwrap()), 6);
        assert_eq!(u16::from_le_bytes(bytes[24..26].try_into().unwrap()), 3);

        let entries = &bytes[26..53];
        assert_eq!(entries[0], b'a');
        assert_eq!(u64::from_le_bytes(entries[1..9].try_into().unwrap()), 3);
        assert_eq!(entries[9], b'b');
        assert_eq!(u64::from_le_bytes(entries[10..18].try_into().unwrap()), 1);
        assert_eq!(entries[18], b'n');
        assert_eq!(u64::from_le_bytes(entries[19..27].try_into().unwrap()), 2);
    }

    #[test]
    fn validates_payload_length_against_encoded_bits() {
        let frequencies = byte_frequencies(b"abc");
        let error = HzArchive::new(0, 3, 9, frequencies, vec![0]).expect_err("invalid length");

        assert_eq!(
            error,
            NativeError::Internal("encoded payload length does not match bit count")
        );
    }
}
