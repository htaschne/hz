use crate::error::NativeError;

pub struct BitReader<'a> {
    data: &'a [u8],
    bit_count: u64,
    bits_read: u64,
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
