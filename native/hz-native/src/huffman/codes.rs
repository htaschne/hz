use crate::error::NativeError;

use super::tree::HuffmanTree;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HuffmanCode {
    bits: Vec<bool>,
}

impl HuffmanCode {
    pub fn new(bits: Vec<bool>) -> Result<Self, NativeError> {
        if bits.is_empty() {
            return Err(NativeError::Internal(
                "Huffman code must contain at least one bit",
            ));
        }

        Ok(Self { bits })
    }

    pub fn bits(&self) -> &[bool] {
        &self.bits
    }

    pub fn bit_len(&self) -> usize {
        self.bits.len()
    }

    #[cfg(test)]
    pub fn is_prefix_of(&self, other: &Self) -> bool {
        self.bit_len() <= other.bit_len() && other.bits.starts_with(&self.bits)
    }
}

pub type CodeTable = Vec<Option<HuffmanCode>>;

pub fn make_tree_code_table(tree: &HuffmanTree) -> Result<CodeTable, NativeError> {
    let mut table = vec![None; 256];
    let mut prefix = Vec::new();
    fill_tree_code_table(tree, &mut prefix, &mut table)?;
    Ok(table)
}

fn fill_tree_code_table(
    tree: &HuffmanTree,
    prefix: &mut Vec<bool>,
    table: &mut CodeTable,
) -> Result<(), NativeError> {
    if let Some(byte) = tree.leaf_byte() {
        let bits = if prefix.is_empty() {
            vec![false]
        } else {
            prefix.clone()
        };
        table[usize::from(byte)] = Some(HuffmanCode::new(bits)?);
        return Ok(());
    }

    if let Some(left) = tree.left() {
        prefix.push(false);
        fill_tree_code_table(left, prefix, table)?;
        prefix.pop();
    }

    if let Some(right) = tree.right() {
        prefix.push(true);
        fill_tree_code_table(right, prefix, table)?;
        prefix.pop();
    }

    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CodeLength {
    pub byte: u8,
    pub bit_len: usize,
}

pub fn code_lengths(tree: &HuffmanTree) -> Vec<CodeLength> {
    let mut lengths = Vec::new();
    let mut depth = 0;
    collect_code_lengths(tree, &mut depth, &mut lengths);
    lengths.sort_by_key(|entry| entry.byte);
    lengths
}

fn collect_code_lengths(tree: &HuffmanTree, depth: &mut usize, lengths: &mut Vec<CodeLength>) {
    if let Some(byte) = tree.leaf_byte() {
        lengths.push(CodeLength {
            byte,
            bit_len: (*depth).max(1),
        });
        return;
    }

    if let Some(left) = tree.left() {
        *depth += 1;
        collect_code_lengths(left, depth, lengths);
        *depth -= 1;
    }

    if let Some(right) = tree.right() {
        *depth += 1;
        collect_code_lengths(right, depth, lengths);
        *depth -= 1;
    }
}

pub fn make_canonical_code_table(lengths: &[CodeLength]) -> Result<CodeTable, NativeError> {
    let mut sorted = lengths.to_vec();
    sorted.sort_by_key(|entry| (entry.bit_len, entry.byte));

    let mut table = vec![None; 256];
    let mut code = Vec::<bool>::new();
    let mut previous_len = 0usize;

    for entry in sorted {
        if entry.bit_len == 0 {
            return Err(NativeError::Internal("Huffman code length cannot be zero"));
        }

        if previous_len == 0 {
            code.resize(entry.bit_len, false);
        } else {
            increment_bits(&mut code)?;
            if entry.bit_len < previous_len {
                return Err(NativeError::Internal(
                    "canonical code lengths are not sorted",
                ));
            }
            code.resize(entry.bit_len, false);
        }

        table[usize::from(entry.byte)] = Some(HuffmanCode::new(code.clone())?);
        previous_len = entry.bit_len;
    }

    Ok(table)
}

fn increment_bits(bits: &mut [bool]) -> Result<(), NativeError> {
    for bit in bits.iter_mut().rev() {
        if *bit {
            *bit = false;
        } else {
            *bit = true;
            return Ok(());
        }
    }

    Err(NativeError::Internal(
        "canonical Huffman code space overflowed",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::huffman::frequency::byte_frequencies;
    use crate::huffman::tree::build_huffman_tree;

    fn table_codes(table: &CodeTable) -> Vec<(u8, Vec<bool>)> {
        table
            .iter()
            .enumerate()
            .filter_map(|(byte, code)| code.as_ref().map(|code| (byte as u8, code.bits().to_vec())))
            .collect()
    }

    #[test]
    fn tree_code_lengths_match_balanced_equal_frequencies() {
        let frequencies = byte_frequencies(b"abcd");
        let tree = build_huffman_tree(&frequencies).expect("tree");

        assert_eq!(
            code_lengths(&tree),
            vec![
                CodeLength {
                    byte: b'a',
                    bit_len: 2
                },
                CodeLength {
                    byte: b'b',
                    bit_len: 2
                },
                CodeLength {
                    byte: b'c',
                    bit_len: 2
                },
                CodeLength {
                    byte: b'd',
                    bit_len: 2
                },
            ]
        );
    }

    #[test]
    fn single_symbol_receives_one_bit_code() {
        let frequencies = byte_frequencies(b"aaaa");
        let tree = build_huffman_tree(&frequencies).expect("tree");
        let table = make_tree_code_table(&tree).expect("table");

        assert_eq!(
            table[usize::from(b'a')].as_ref().map(HuffmanCode::bits),
            Some(&[false][..])
        );
        assert_eq!(
            code_lengths(&tree),
            vec![CodeLength {
                byte: b'a',
                bit_len: 1
            }]
        );
    }

    #[test]
    fn canonical_codes_are_ordered_by_length_then_byte() {
        let table = make_canonical_code_table(&[
            CodeLength {
                byte: b'c',
                bit_len: 3,
            },
            CodeLength {
                byte: b'a',
                bit_len: 2,
            },
            CodeLength {
                byte: b'b',
                bit_len: 2,
            },
        ])
        .expect("canonical table");

        assert_eq!(
            table_codes(&table),
            vec![
                (b'a', vec![false, false]),
                (b'b', vec![false, true]),
                (b'c', vec![true, false, false]),
            ]
        );
    }

    #[test]
    fn code_table_is_prefix_free() {
        let frequencies = byte_frequencies(b"banana");
        let tree = build_huffman_tree(&frequencies).expect("tree");
        let table = make_tree_code_table(&tree).expect("table");
        let codes: Vec<_> = table.iter().filter_map(Option::as_ref).collect();

        for (index, lhs) in codes.iter().enumerate() {
            for (other_index, rhs) in codes.iter().enumerate() {
                if index != other_index {
                    assert!(!lhs.is_prefix_of(rhs));
                }
            }
        }
    }

    #[test]
    fn equal_frequency_code_generation_is_deterministic() {
        let frequencies = byte_frequencies(b"abcd");
        let first_tree = build_huffman_tree(&frequencies).expect("tree");
        let second_tree = build_huffman_tree(&frequencies).expect("tree");

        assert_eq!(
            make_tree_code_table(&first_tree).expect("first"),
            make_tree_code_table(&second_tree).expect("second")
        );
    }
}
