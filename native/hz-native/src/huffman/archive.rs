use std::io::Read;
use std::io::Write;

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
        let mut output = Vec::new();
        self.write_to(&mut output)?;
        Ok(output)
    }

    pub fn write_to<W: Write>(&self, output: &mut W) -> Result<u64, NativeError> {
        write_archive_header(
            output,
            self.recursive_layer_count,
            self.original_byte_count,
            self.encoded_bit_count,
            &self.frequencies,
        )?;
        output
            .write_all(&self.payload)
            .map_err(|_| NativeError::Internal("failed to write archive payload"))?;
        archive_header_length(&self.frequencies)
            .and_then(|header_len| checked_add_u64(header_len, self.payload.len() as u64))
    }

    pub fn parse(data: &[u8]) -> Result<Self, NativeError> {
        let mut reader = ArchiveReader::new(data);
        let header = read_archive_header(&mut reader)?;
        let expected_payload_len = expected_payload_length(header.encoded_bit_count)?;
        let payload = reader.read_remaining();
        if payload.len() != expected_payload_len {
            return Err(NativeError::InvalidArgument(
                "Hz payload length does not match encoded bit count",
            ));
        }

        Ok(Self {
            recursive_layer_count: header.recursive_layer_count,
            original_byte_count: header.original_byte_count,
            encoded_bit_count: header.encoded_bit_count,
            frequencies: header.frequencies,
            payload: payload.to_vec(),
        })
    }

    pub fn original_byte_count(&self) -> u64 {
        self.original_byte_count
    }

    pub fn encoded_bit_count(&self) -> u64 {
        self.encoded_bit_count
    }

    pub fn frequencies(&self) -> &FrequencyTable {
        &self.frequencies
    }

    pub fn payload(&self) -> &[u8] {
        &self.payload
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HzArchiveHeader {
    pub recursive_layer_count: u16,
    pub original_byte_count: u64,
    pub encoded_bit_count: u64,
    pub frequencies: FrequencyTable,
    pub header_byte_count: u64,
    pub payload_byte_count: u64,
}

pub fn write_archive_header<W: Write>(
    output: &mut W,
    recursive_layer_count: u16,
    original_byte_count: u64,
    encoded_bit_count: u64,
    frequencies: &FrequencyTable,
) -> Result<u64, NativeError> {
    let entry_count = frequencies
        .iter()
        .filter(|&&frequency| frequency > 0)
        .count();
    let entry_count = u16::try_from(entry_count)
        .map_err(|_| NativeError::Internal("frequency table has too many entries"))?;

    output
        .write_all(&HzArchive::MAGIC)
        .map_err(|_| NativeError::Internal("failed to write archive header"))?;
    output
        .write_all(&[HzArchive::VERSION, HzArchive::FLAGS])
        .map_err(|_| NativeError::Internal("failed to write archive header"))?;
    output
        .write_all(&recursive_layer_count.to_le_bytes())
        .map_err(|_| NativeError::Internal("failed to write archive header"))?;
    output
        .write_all(&original_byte_count.to_le_bytes())
        .map_err(|_| NativeError::Internal("failed to write archive header"))?;
    output
        .write_all(&encoded_bit_count.to_le_bytes())
        .map_err(|_| NativeError::Internal("failed to write archive header"))?;
    output
        .write_all(&entry_count.to_le_bytes())
        .map_err(|_| NativeError::Internal("failed to write archive header"))?;

    for (byte, &frequency) in frequencies.iter().enumerate() {
        if frequency == 0 {
            continue;
        }

        output
            .write_all(&[byte as u8])
            .map_err(|_| NativeError::Internal("failed to write archive header"))?;
        output
            .write_all(&frequency.to_le_bytes())
            .map_err(|_| NativeError::Internal("failed to write archive header"))?;
    }

    archive_header_length(frequencies)
}

pub fn read_archive_header<R: ArchiveRead>(reader: &mut R) -> Result<HzArchiveHeader, NativeError> {
    let magic = reader.read_bytes(HzArchive::MAGIC.len())?;
    if magic != HzArchive::MAGIC {
        return Err(NativeError::InvalidArgument(
            "unsupported legacy or invalid Hz archive",
        ));
    }

    let version = reader.read_u8()?;
    if version != HzArchive::VERSION {
        return Err(NativeError::InvalidArgument(
            "unsupported Hz archive version",
        ));
    }

    let flags = reader.read_u8()?;
    let recursive_layer_count = reader.read_u16()?;
    let original_byte_count = reader.read_u64()?;
    let encoded_bit_count = reader.read_u64()?;
    let entry_count = reader.read_u16()?;

    if flags != HzArchive::FLAGS {
        return Err(NativeError::InvalidArgument("unsupported Hz archive flags"));
    }

    if recursive_layer_count == 0 && original_byte_count == 0 && encoded_bit_count != 0 {
        return Err(NativeError::InvalidArgument(
            "invalid recursive layer count in Hz archive",
        ));
    }

    let mut frequencies = [0; 256];
    for _ in 0..entry_count {
        let byte = reader.read_u8()?;
        let frequency = reader.read_u64()?;
        if frequency == 0 {
            return Err(NativeError::InvalidArgument("invalid Hz frequency table"));
        }

        let slot = &mut frequencies[usize::from(byte)];
        if *slot != 0 {
            return Err(NativeError::InvalidArgument(
                "duplicate Hz frequency table entry",
            ));
        }

        *slot = frequency;
    }

    let frequency_total = checked_total_frequency(&frequencies)?;
    if frequency_total != original_byte_count {
        return Err(NativeError::InvalidArgument(
            "Hz frequency total does not match original byte count",
        ));
    }

    if original_byte_count == 0 {
        if frequencies.iter().any(|&frequency| frequency > 0) || encoded_bit_count != 0 {
            return Err(NativeError::InvalidArgument("invalid Hz frequency table"));
        }
    } else if frequencies.iter().all(|&frequency| frequency == 0) || encoded_bit_count == 0 {
        return Err(NativeError::InvalidArgument(
            "invalid encoded bit count in Hz archive",
        ));
    }

    let payload_byte_count = expected_payload_length(encoded_bit_count)? as u64;
    Ok(HzArchiveHeader {
        recursive_layer_count,
        original_byte_count,
        encoded_bit_count,
        frequencies,
        header_byte_count: archive_header_length(&frequencies)?,
        payload_byte_count,
    })
}

fn expected_payload_length(encoded_bit_count: u64) -> Result<usize, NativeError> {
    let length = encoded_bit_count / 8 + u64::from(!encoded_bit_count.is_multiple_of(8));
    usize::try_from(length).map_err(|_| NativeError::Internal("encoded payload is too large"))
}

pub fn payload_length(encoded_bit_count: u64) -> Result<u64, NativeError> {
    expected_payload_length(encoded_bit_count).map(|length| length as u64)
}

pub fn archive_header_length(frequencies: &FrequencyTable) -> Result<u64, NativeError> {
    let entry_count = frequencies
        .iter()
        .filter(|&&frequency| frequency > 0)
        .count();
    let entry_count = u64::try_from(entry_count)
        .map_err(|_| NativeError::Internal("frequency table has too many entries"))?;
    checked_add_u64(
        26,
        entry_count
            .checked_mul(9)
            .ok_or(NativeError::Internal("archive header length overflowed"))?,
    )
}

fn checked_add_u64(lhs: u64, rhs: u64) -> Result<u64, NativeError> {
    lhs.checked_add(rhs)
        .ok_or(NativeError::Internal("archive length overflowed"))
}

pub trait ArchiveRead {
    fn read_u8(&mut self) -> Result<u8, NativeError>;
    fn read_u16(&mut self) -> Result<u16, NativeError>;
    fn read_u64(&mut self) -> Result<u64, NativeError>;
    fn read_bytes(&mut self, count: usize) -> Result<Vec<u8>, NativeError>;
}

pub struct StreamingArchiveReader<'a, R> {
    inner: &'a mut R,
}

impl<'a, R: Read> StreamingArchiveReader<'a, R> {
    pub fn new(inner: &'a mut R) -> Self {
        Self { inner }
    }
}

impl<R: Read> ArchiveRead for StreamingArchiveReader<'_, R> {
    fn read_u8(&mut self) -> Result<u8, NativeError> {
        let mut byte = [0];
        self.inner
            .read_exact(&mut byte)
            .map_err(|_| NativeError::InvalidArgument("truncated Hz archive header"))?;
        Ok(byte[0])
    }

    fn read_u16(&mut self) -> Result<u16, NativeError> {
        let bytes = self.read_bytes(2)?;
        Ok(u16::from_le_bytes(bytes.try_into().expect("two bytes")))
    }

    fn read_u64(&mut self) -> Result<u64, NativeError> {
        let bytes = self.read_bytes(8)?;
        Ok(u64::from_le_bytes(bytes.try_into().expect("eight bytes")))
    }

    fn read_bytes(&mut self, count: usize) -> Result<Vec<u8>, NativeError> {
        let mut bytes = vec![0; count];
        self.inner
            .read_exact(&mut bytes)
            .map_err(|_| NativeError::InvalidArgument("truncated Hz archive header"))?;
        Ok(bytes)
    }
}

fn checked_total_frequency(frequencies: &FrequencyTable) -> Result<u64, NativeError> {
    frequencies.iter().try_fold(0_u64, |total, &frequency| {
        total
            .checked_add(frequency)
            .ok_or(NativeError::InvalidArgument(
                "Hz frequency total overflowed",
            ))
    })
}

struct ArchiveReader<'a> {
    data: &'a [u8],
    offset: usize,
}

impl<'a> ArchiveReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, offset: 0 }
    }

    fn read_u8(&mut self) -> Result<u8, NativeError> {
        let byte = self
            .data
            .get(self.offset)
            .copied()
            .ok_or(NativeError::InvalidArgument("truncated Hz archive header"))?;
        self.offset += 1;
        Ok(byte)
    }

    fn read_u16(&mut self) -> Result<u16, NativeError> {
        let bytes = self.read_bytes(2)?;
        Ok(u16::from_le_bytes(bytes.try_into().expect("two bytes")))
    }

    fn read_u64(&mut self) -> Result<u64, NativeError> {
        let bytes = self.read_bytes(8)?;
        Ok(u64::from_le_bytes(bytes.try_into().expect("eight bytes")))
    }

    fn read_bytes(&mut self, count: usize) -> Result<&'a [u8], NativeError> {
        let end = self
            .offset
            .checked_add(count)
            .ok_or(NativeError::InvalidArgument("truncated Hz archive header"))?;
        let bytes = self
            .data
            .get(self.offset..end)
            .ok_or(NativeError::InvalidArgument("truncated Hz archive header"))?;
        self.offset = end;
        Ok(bytes)
    }

    fn read_remaining(&mut self) -> &'a [u8] {
        let remaining = &self.data[self.offset..];
        self.offset = self.data.len();
        remaining
    }
}

impl ArchiveRead for ArchiveReader<'_> {
    fn read_u8(&mut self) -> Result<u8, NativeError> {
        ArchiveReader::read_u8(self)
    }

    fn read_u16(&mut self) -> Result<u16, NativeError> {
        ArchiveReader::read_u16(self)
    }

    fn read_u64(&mut self) -> Result<u64, NativeError> {
        ArchiveReader::read_u64(self)
    }

    fn read_bytes(&mut self, count: usize) -> Result<Vec<u8>, NativeError> {
        ArchiveReader::read_bytes(self, count).map(<[u8]>::to_vec)
    }
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

    #[test]
    fn parses_serialized_archive() {
        let bytes = archive_for(b"banana").serialize().expect("serialize");
        let archive = HzArchive::parse(&bytes).expect("parse");

        assert_eq!(archive.original_byte_count(), 6);
        assert_eq!(archive.frequencies()[usize::from(b'a')], 3);
        assert_eq!(archive.frequencies()[usize::from(b'b')], 1);
        assert_eq!(archive.frequencies()[usize::from(b'n')], 2);
        assert_eq!(archive.payload().len(), 2);
    }

    #[test]
    fn rejects_invalid_magic() {
        let mut bytes = archive_for(b"abc").serialize().expect("serialize");
        bytes[0] = b'X';

        assert_eq!(
            HzArchive::parse(&bytes).expect_err("invalid magic"),
            NativeError::InvalidArgument("unsupported legacy or invalid Hz archive")
        );
    }

    #[test]
    fn rejects_truncated_header() {
        let bytes = vec![b'H', b'Z', b'F'];

        assert_eq!(
            HzArchive::parse(&bytes).expect_err("truncated"),
            NativeError::InvalidArgument("truncated Hz archive header")
        );
    }

    #[test]
    fn rejects_payload_length_mismatch() {
        let mut bytes = archive_for(b"abc").serialize().expect("serialize");
        bytes.pop();

        assert_eq!(
            HzArchive::parse(&bytes).expect_err("payload mismatch"),
            NativeError::InvalidArgument("Hz payload length does not match encoded bit count")
        );
    }

    #[test]
    fn golden_empty_archive_matches_specification() {
        assert_eq!(
            archive_for(b"").serialize().expect("serialize"),
            vec![
                0x48, 0x5A, 0x46, 0x31, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            ]
        );
    }

    #[test]
    fn golden_single_symbol_archive_matches_specification() {
        assert_eq!(
            archive_for(b"aaaa").serialize().expect("serialize"),
            vec![
                0x48, 0x5A, 0x46, 0x31, 0x02, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x61, 0x04,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            ]
        );
    }

    #[test]
    fn golden_banana_archive_matches_specification() {
        assert_eq!(
            archive_for(b"banana").serialize().expect("serialize"),
            vec![
                0x48, 0x5A, 0x46, 0x31, 0x02, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x61, 0x03,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x62, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x6E, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9B, 0x00,
            ]
        );
    }
}
