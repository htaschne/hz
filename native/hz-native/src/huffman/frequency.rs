pub type FrequencyTable = [u64; 256];

pub fn byte_frequencies(input: &[u8]) -> FrequencyTable {
    let mut frequencies = [0; 256];

    for &byte in input {
        frequencies[usize::from(byte)] += 1;
    }

    frequencies
}

pub fn total_frequency(frequencies: &FrequencyTable) -> u64 {
    frequencies.iter().sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_frequency_table_has_zero_total() {
        let frequencies = byte_frequencies(&[]);

        assert_eq!(total_frequency(&frequencies), 0);
    }

    #[test]
    fn counts_all_byte_values() {
        let input: Vec<u8> = (0..=255).collect();
        let frequencies = byte_frequencies(&input);

        assert!(frequencies.iter().all(|&frequency| frequency == 1));
        assert_eq!(total_frequency(&frequencies), 256);
    }
}
