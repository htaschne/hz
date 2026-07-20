use std::io::Cursor;
use std::io::Read;
use std::io::Seek;
use std::io::SeekFrom;
use std::io::Write;

use crate::error::NativeError;

use super::archive::archive_header_length;
use super::archive::payload_length;
use super::archive::read_archive_header;
use super::archive::write_archive_header;
use super::archive::StreamingArchiveReader;
use super::bit_reader::StreamingBitReader;
use super::bit_writer::BitWriter;
use super::codes::code_lengths;
use super::codes::make_canonical_code_table;
use super::codes::make_tree_code_table;
use super::codes::CodeTable;
use super::frequency::FrequencyTable;
use super::tree::build_huffman_tree;
use super::tree::HuffmanTree;

pub const STREAM_BUFFER_SIZE: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CompressionStats {
    pub input_bytes: u64,
    pub output_bytes: u64,
    pub header_bytes: u64,
    pub payload_bytes: u64,
    pub encoded_bit_count: u64,
    pub padding_bit_count: u8,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DecompressionStats {
    pub input_bytes: u64,
    pub output_bytes: u64,
}

pub fn compress_to_vec(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    let mut reader = Cursor::new(input);
    let mut output = Vec::new();
    compress_stream(&mut reader, &mut output)?;
    Ok(output)
}

pub fn decompress_to_vec(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    let mut reader = Cursor::new(input);
    let mut output = Vec::new();
    decompress_stream(&mut reader, &mut output)?;
    Ok(output)
}

pub fn compress_stream<R, W>(input: &mut R, output: &mut W) -> Result<CompressionStats, NativeError>
where
    R: Read + Seek,
    W: Write,
{
    let start_position = input
        .stream_position()
        .map_err(|_| NativeError::Internal("failed to query input stream position"))?;
    let frequencies = count_stream_frequencies(input)?;
    let input_bytes = checked_total_frequency(&frequencies)?;

    input
        .seek(SeekFrom::Start(start_position))
        .map_err(|_| NativeError::Internal("failed to seek input stream"))?;

    let (code_table, encoded_bit_count) = code_table_and_bit_count(&frequencies)?;
    let header_bytes =
        write_archive_header(output, 0, input_bytes, encoded_bit_count, &frequencies)?;

    let payload_stats = if input_bytes == 0 {
        super::bit_writer::BitWriterStats {
            bit_count: 0,
            bytes_written: 0,
            padding_bit_count: 0,
        }
    } else {
        encode_stream_payload(input, output, &code_table)?
    };

    debug_assert_eq!(payload_stats.bit_count, encoded_bit_count);
    let payload_bytes = payload_stats.bytes_written;
    let output_bytes = header_bytes
        .checked_add(payload_bytes)
        .ok_or(NativeError::Internal("archive length overflowed"))?;

    Ok(CompressionStats {
        input_bytes,
        output_bytes,
        header_bytes,
        payload_bytes,
        encoded_bit_count,
        padding_bit_count: payload_stats.padding_bit_count,
    })
}

pub fn decompress_stream<R, W>(
    input: &mut R,
    output: &mut W,
) -> Result<DecompressionStats, NativeError>
where
    R: Read,
    W: Write,
{
    let mut header_reader = StreamingArchiveReader::new(input);
    let header = read_archive_header(&mut header_reader)?;
    let input_bytes = header
        .header_byte_count
        .checked_add(header.payload_byte_count)
        .ok_or(NativeError::Internal("archive length overflowed"))?;

    if header.original_byte_count == 0 {
        return Ok(DecompressionStats {
            input_bytes,
            output_bytes: 0,
        });
    }

    let tree = build_huffman_tree(&header.frequencies)
        .ok_or(NativeError::InvalidArgument("missing Huffman tree"))?;
    let mut decoded = OutputBuffer::new(output);

    if let Some(byte) = tree.leaf_byte() {
        decode_single_symbol_stream(byte, input, &mut decoded, header.encoded_bit_count)?;
    } else {
        decode_tree_stream(
            &tree,
            input,
            &mut decoded,
            header.encoded_bit_count,
            header.original_byte_count,
        )?;
    }

    decoded.flush()?;

    Ok(DecompressionStats {
        input_bytes,
        output_bytes: header.original_byte_count,
    })
}

fn count_stream_frequencies<R: Read>(input: &mut R) -> Result<FrequencyTable, NativeError> {
    let mut frequencies = [0; 256];
    let mut buffer = [0; STREAM_BUFFER_SIZE];

    loop {
        let count = input
            .read(&mut buffer)
            .map_err(|_| NativeError::Internal("failed to read input stream"))?;
        if count == 0 {
            return Ok(frequencies);
        }

        for &byte in &buffer[..count] {
            let slot = &mut frequencies[usize::from(byte)];
            *slot = slot
                .checked_add(1)
                .ok_or(NativeError::Internal("input byte count overflowed"))?;
        }
    }
}

fn code_table_and_bit_count(frequencies: &FrequencyTable) -> Result<(CodeTable, u64), NativeError> {
    let Some(tree) = build_huffman_tree(frequencies) else {
        return Ok((vec![None; 256], 0));
    };

    let code_table = make_tree_code_table(&tree)?;
    let lengths = code_lengths(&tree);
    let canonical_table = make_canonical_code_table(&lengths)?;
    debug_assert_eq!(
        code_table.iter().filter(|code| code.is_some()).count(),
        canonical_table.iter().filter(|code| code.is_some()).count()
    );

    let mut bit_count = 0_u64;
    for (byte, code) in code_table.iter().enumerate() {
        let Some(code) = code else {
            continue;
        };
        let frequency = frequencies[byte];
        let code_len = u64::try_from(code.bit_len())
            .map_err(|_| NativeError::Internal("encoded bit count overflowed"))?;
        bit_count = bit_count
            .checked_add(
                frequency
                    .checked_mul(code_len)
                    .ok_or(NativeError::Internal("encoded bit count overflowed"))?,
            )
            .ok_or(NativeError::Internal("encoded bit count overflowed"))?;
    }

    Ok((code_table, bit_count))
}

fn encode_stream_payload<R: Read, W: Write>(
    input: &mut R,
    output: &mut W,
    code_table: &CodeTable,
) -> Result<super::bit_writer::BitWriterStats, NativeError> {
    let mut buffer = [0; STREAM_BUFFER_SIZE];
    let mut writer = BitWriter::new(output);

    loop {
        let count = input
            .read(&mut buffer)
            .map_err(|_| NativeError::Internal("failed to read input stream"))?;
        if count == 0 {
            return writer.finish();
        }

        for &byte in &buffer[..count] {
            let code = code_table
                .get(usize::from(byte))
                .and_then(Option::as_ref)
                .ok_or(NativeError::Internal("missing Huffman code for input byte"))?;
            writer.write_code(code)?;
        }
    }
}

fn decode_tree_stream<R: Read, W: Write>(
    tree: &HuffmanTree,
    input: &mut R,
    output: &mut OutputBuffer<'_, W>,
    encoded_bit_count: u64,
    original_byte_count: u64,
) -> Result<(), NativeError> {
    let mut reader = StreamingBitReader::new(input, encoded_bit_count);
    let mut node = tree;
    let mut decoded_count = 0_u64;

    for _ in 0..encoded_bit_count {
        let bit = reader.read_bit()?;
        node = next_node(node, bit)?;

        if let Some(byte) = node.leaf_byte() {
            output.write_byte(byte)?;
            decoded_count = decoded_count
                .checked_add(1)
                .ok_or(NativeError::InvalidArgument("decoded output is too large"))?;
            if decoded_count > original_byte_count {
                return Err(NativeError::InvalidArgument("invalid Huffman bitstream"));
            }

            if decoded_count == original_byte_count {
                reader.discard_remaining_payload_bytes()?;
                return Ok(());
            }

            node = tree;
        }
    }

    Err(NativeError::InvalidArgument("invalid Huffman bitstream"))
}

fn decode_single_symbol_stream<R: Read, W: Write>(
    byte: u8,
    input: &mut R,
    output: &mut OutputBuffer<'_, W>,
    encoded_bit_count: u64,
) -> Result<(), NativeError> {
    let mut reader = StreamingBitReader::new(input, encoded_bit_count);

    for _ in 0..encoded_bit_count {
        if reader.read_bit()? {
            return Err(NativeError::InvalidArgument(
                "invalid single-symbol Huffman bitstream",
            ));
        }
        output.write_byte(byte)?;
    }

    Ok(())
}

fn next_node(tree: &HuffmanTree, bit: bool) -> Result<&HuffmanTree, NativeError> {
    let child = if bit { tree.right() } else { tree.left() };
    child.ok_or(NativeError::InvalidArgument("invalid Huffman bitstream"))
}

fn checked_total_frequency(frequencies: &FrequencyTable) -> Result<u64, NativeError> {
    frequencies.iter().try_fold(0_u64, |total, &frequency| {
        total
            .checked_add(frequency)
            .ok_or(NativeError::Internal("input byte count overflowed"))
    })
}

struct OutputBuffer<'a, W> {
    inner: &'a mut W,
    bytes: Vec<u8>,
}

impl<'a, W: Write> OutputBuffer<'a, W> {
    fn new(inner: &'a mut W) -> Self {
        Self {
            inner,
            bytes: Vec::with_capacity(STREAM_BUFFER_SIZE),
        }
    }

    fn write_byte(&mut self, byte: u8) -> Result<(), NativeError> {
        self.bytes.push(byte);
        if self.bytes.len() == STREAM_BUFFER_SIZE {
            self.flush()?;
        }
        Ok(())
    }

    fn flush(&mut self) -> Result<(), NativeError> {
        if self.bytes.is_empty() {
            return Ok(());
        }

        self.inner
            .write_all(&self.bytes)
            .map_err(|_| NativeError::Internal("failed to write decoded output"))?;
        self.bytes.clear();
        Ok(())
    }
}

#[allow(dead_code)]
fn _assert_archive_lengths_compile(frequencies: &FrequencyTable, encoded_bit_count: u64) {
    let _ = archive_header_length(frequencies);
    let _ = payload_length(encoded_bit_count);
}

#[cfg(test)]
mod tests {
    use std::cmp::min;
    use std::io;

    use super::*;
    use crate::huffman::compress;
    use crate::huffman::decompress;

    #[test]
    fn streaming_compression_matches_in_memory_output() {
        let input = b"banana banana banana";
        let expected = compress(input).expect("compress");
        let mut reader = Cursor::new(input);
        let mut output = Vec::new();

        let stats = compress_stream(&mut reader, &mut output).expect("stream compress");

        assert_eq!(output, expected);
        assert_eq!(stats.input_bytes, input.len() as u64);
        assert_eq!(stats.output_bytes, output.len() as u64);
    }

    #[test]
    fn streaming_compression_starts_at_current_position() {
        let input = b"skip:banana";
        let expected = compress(b"banana").expect("compress");
        let mut reader = Cursor::new(input);
        reader.set_position(5);
        let mut output = Vec::new();

        compress_stream(&mut reader, &mut output).expect("stream compress");

        assert_eq!(output, expected);
    }

    #[test]
    fn streaming_compression_uses_multiple_reads() {
        let input = vec![b'a'; STREAM_BUFFER_SIZE + 17];
        let mut reader = LimitedReadSeek::new(input.clone(), STREAM_BUFFER_SIZE);
        let mut output = Vec::new();

        let stats = compress_stream(&mut reader, &mut output).expect("stream compress");
        let decoded = decompress(&output).expect("decompress");

        assert_eq!(decoded, input);
        assert!(reader.read_calls > 4);
        assert_eq!(stats.input_bytes, input.len() as u64);
    }

    #[test]
    fn streaming_decompression_writes_in_chunks() {
        let input = vec![0_u8, 1, 0, 2, 0, 3, 255, 0];
        let archive = compress(&input).expect("compress");
        let mut reader = LimitedRead::new(archive, 64);
        let mut writer = PartialWriter::new(2);

        let stats = decompress_stream(&mut reader, &mut writer).expect("stream decompress");

        assert_eq!(writer.bytes, input);
        assert!(reader.read_calls > 4);
        assert!(writer.write_calls > 1);
        assert_eq!(stats.output_bytes, 8);
    }

    #[test]
    fn streaming_round_trips_all_byte_values() {
        let input: Vec<u8> = (0..=255).collect();
        let mut reader = Cursor::new(input.clone());
        let mut archive = Vec::new();
        compress_stream(&mut reader, &mut archive).expect("stream compress");
        let mut archive_reader = Cursor::new(archive);
        let mut output = Vec::new();
        decompress_stream(&mut archive_reader, &mut output).expect("stream decompress");

        assert_eq!(output, input);
    }

    #[test]
    fn streaming_decompression_rejects_truncated_payload() {
        let mut archive = compress(b"truncated").expect("compress");
        archive.pop();
        let mut reader = Cursor::new(archive);
        let mut output = Vec::new();

        assert!(decompress_stream(&mut reader, &mut output).is_err());
    }

    #[test]
    fn streaming_decompression_rejects_invalid_single_symbol_padding() {
        let mut archive = compress(b"aaaa").expect("compress");
        let last = archive.len() - 1;
        archive[last] = 0b0001_0000;
        let mut reader = Cursor::new(archive);
        let mut output = Vec::new();

        assert!(decompress_stream(&mut reader, &mut output).is_err());
    }

    struct LimitedRead {
        bytes: Vec<u8>,
        offset: usize,
        max_read: usize,
        read_calls: usize,
    }

    impl LimitedRead {
        fn new(bytes: Vec<u8>, max_read: usize) -> Self {
            Self {
                bytes,
                offset: 0,
                max_read,
                read_calls: 0,
            }
        }
    }

    impl Read for LimitedRead {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            self.read_calls += 1;
            if buffer.len() > self.max_read {
                return Err(io::Error::other("oversized read"));
            }
            if self.offset == self.bytes.len() {
                return Ok(0);
            }

            let count = min(buffer.len(), self.bytes.len() - self.offset);
            buffer[..count].copy_from_slice(&self.bytes[self.offset..self.offset + count]);
            self.offset += count;
            Ok(count)
        }
    }

    struct LimitedReadSeek {
        inner: LimitedRead,
        read_calls: usize,
    }

    impl LimitedReadSeek {
        fn new(bytes: Vec<u8>, max_read: usize) -> Self {
            Self {
                inner: LimitedRead::new(bytes, max_read),
                read_calls: 0,
            }
        }
    }

    impl Read for LimitedReadSeek {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            let count = self.inner.read(buffer)?;
            self.read_calls = self.inner.read_calls;
            Ok(count)
        }
    }

    impl Seek for LimitedReadSeek {
        fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
            let len = self.inner.bytes.len() as i64;
            let current = self.inner.offset as i64;
            let next = match position {
                SeekFrom::Start(offset) => offset as i64,
                SeekFrom::End(offset) => len + offset,
                SeekFrom::Current(offset) => current + offset,
            };

            if !(0..=len).contains(&next) {
                return Err(io::Error::other("invalid seek"));
            }

            self.inner.offset = next as usize;
            Ok(self.inner.offset as u64)
        }
    }

    struct PartialWriter {
        bytes: Vec<u8>,
        max_write: usize,
        write_calls: usize,
    }

    impl PartialWriter {
        fn new(max_write: usize) -> Self {
            Self {
                bytes: Vec::new(),
                max_write,
                write_calls: 0,
            }
        }
    }

    impl Write for PartialWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.write_calls += 1;
            let count = min(bytes.len(), self.max_write);
            self.bytes.extend_from_slice(&bytes[..count]);
            Ok(count)
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
}
