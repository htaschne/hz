use std::io::Read;

use crate::error::NativeError;

pub struct BitReader<'a> {
    data: &'a [u8],
    bit_count: u64,
    bits_read: u64,
}

pub struct StreamingBitReader<'a, R> {
    inner: &'a mut R,
    bit_count: u64,
    bits_read: u64,
    current_byte: u8,
    bit_index: u8,
}

impl<'a, R: Read> StreamingBitReader<'a, R> {
    pub fn new(inner: &'a mut R, bit_count: u64) -> Self {
        Self {
            inner,
            bit_count,
            bits_read: 0,
            current_byte: 0,
            bit_index: 8,
        }
    }

    pub fn read_bit(&mut self) -> Result<bool, NativeError> {
        if self.bits_read >= self.bit_count {
            return Err(NativeError::InvalidArgument(
                "read past end of Huffman bitstream",
            ));
        }

        if self.bit_index == 8 {
            let mut byte = [0];
            self.inner
                .read_exact(&mut byte)
                .map_err(|_| NativeError::InvalidArgument("truncated Hz archive payload"))?;
            self.current_byte = byte[0];
            self.bit_index = 0;
        }

        let shift = 7 - self.bit_index;
        let bit = ((self.current_byte >> shift) & 1) == 1;
        self.bit_index += 1;
        self.bits_read += 1;
        Ok(bit)
    }

    pub fn discard_remaining_payload_bytes(&mut self) -> Result<(), NativeError> {
        let consumed_payload_bytes =
            self.bits_read / 8 + u64::from(self.bit_index > 0 && self.bit_index < 8);
        let payload_bytes = self.bit_count / 8 + u64::from(!self.bit_count.is_multiple_of(8));
        let remaining = payload_bytes.saturating_sub(consumed_payload_bytes);
        let mut buffer = [0; 8192];
        let mut remaining = usize::try_from(remaining)
            .map_err(|_| NativeError::InvalidArgument("Huffman bitstream is too large"))?;

        while remaining > 0 {
            let count = remaining.min(buffer.len());
            self.inner
                .read_exact(&mut buffer[..count])
                .map_err(|_| NativeError::InvalidArgument("truncated Hz archive payload"))?;
            remaining -= count;
        }

        Ok(())
    }
}

impl<'a> BitReader<'a> {
    pub fn new(data: &'a [u8], bit_count: u64) -> Self {
        Self {
            data,
            bit_count,
            bits_read: 0,
        }
    }

    pub fn read_bit(&mut self) -> Result<bool, NativeError> {
        if self.bits_read >= self.bit_count {
            return Err(NativeError::InvalidArgument(
                "read past end of Huffman bitstream",
            ));
        }

        let byte_index = usize::try_from(self.bits_read / 8)
            .map_err(|_| NativeError::InvalidArgument("Huffman bitstream is too large"))?;
        let byte = self
            .data
            .get(byte_index)
            .ok_or(NativeError::InvalidArgument(
                "read past end of Huffman bitstream",
            ))?;
        let shift = 7 - (self.bits_read % 8);
        let bit = ((byte >> shift) & 1) == 1;
        self.bits_read += 1;
        Ok(bit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_bits_most_significant_first() {
        let mut reader = BitReader::new(&[0b1010_0000], 3);

        assert!(reader.read_bit().expect("bit"));
        assert!(!reader.read_bit().expect("bit"));
        assert!(reader.read_bit().expect("bit"));
    }

    #[test]
    fn refuses_to_read_padding_bits() {
        let mut reader = BitReader::new(&[0b1000_0000], 1);

        assert!(reader.read_bit().expect("bit"));
        assert_eq!(
            reader.read_bit().expect_err("past end"),
            NativeError::InvalidArgument("read past end of Huffman bitstream")
        );
    }
}
