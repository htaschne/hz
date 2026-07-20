use std::cmp::Ordering;
use std::cmp::Reverse;
use std::collections::BinaryHeap;

use super::frequency::FrequencyTable;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HuffmanTree {
    Leaf {
        byte: u8,
        frequency: u64,
    },
    Branch {
        frequency: u64,
        minimum_byte: u8,
        left: Box<HuffmanTree>,
        right: Box<HuffmanTree>,
    },
}

impl HuffmanTree {
    pub fn frequency(&self) -> u64 {
        match self {
            Self::Leaf { frequency, .. } | Self::Branch { frequency, .. } => *frequency,
        }
    }

    #[cfg(test)]
    pub fn minimum_byte(&self) -> u8 {
        match self {
            Self::Leaf { byte, .. } => *byte,
            Self::Branch { minimum_byte, .. } => *minimum_byte,
        }
    }

    pub fn leaf_byte(&self) -> Option<u8> {
        match self {
            Self::Leaf { byte, .. } => Some(*byte),
            Self::Branch { .. } => None,
        }
    }

    pub fn left(&self) -> Option<&HuffmanTree> {
        match self {
            Self::Branch { left, .. } => Some(left),
            Self::Leaf { .. } => None,
        }
    }

    pub fn right(&self) -> Option<&HuffmanTree> {
        match self {
            Self::Branch { right, .. } => Some(right),
            Self::Leaf { .. } => None,
        }
    }
}

#[derive(Debug)]
struct HeapEntry {
    frequency: u64,
    minimum_byte: u8,
    sequence: usize,
    tree: HuffmanTree,
}

impl PartialEq for HeapEntry {
    fn eq(&self, other: &Self) -> bool {
        self.frequency == other.frequency
            && self.minimum_byte == other.minimum_byte
            && self.sequence == other.sequence
    }
}

impl Eq for HeapEntry {}

impl PartialOrd for HeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for HeapEntry {
    fn cmp(&self, other: &Self) -> Ordering {
        self.frequency
            .cmp(&other.frequency)
            .then_with(|| self.minimum_byte.cmp(&other.minimum_byte))
            .then_with(|| self.sequence.cmp(&other.sequence))
    }
}

pub fn build_huffman_tree(frequencies: &FrequencyTable) -> Option<HuffmanTree> {
    let mut heap = BinaryHeap::new();
    let mut next_sequence = 0;

    for (byte, &frequency) in frequencies.iter().enumerate() {
        if frequency == 0 {
            continue;
        }

        let byte = byte as u8;
        heap.push(Reverse(HeapEntry {
            frequency,
            minimum_byte: byte,
            sequence: next_sequence,
            tree: HuffmanTree::Leaf { byte, frequency },
        }));
        next_sequence += 1;
    }

    while heap.len() > 1 {
        let Reverse(left) = heap.pop()?;
        let Reverse(right) = heap.pop()?;
        let frequency = left.frequency + right.frequency;
        let minimum_byte = left.minimum_byte.min(right.minimum_byte);

        heap.push(Reverse(HeapEntry {
            frequency,
            minimum_byte,
            sequence: next_sequence,
            tree: HuffmanTree::Branch {
                frequency,
                minimum_byte,
                left: Box::new(left.tree),
                right: Box::new(right.tree),
            },
        }));
        next_sequence += 1;
    }

    heap.pop().map(|Reverse(entry)| entry.tree)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::huffman::frequency::byte_frequencies;

    #[test]
    fn empty_input_has_no_tree() {
        let frequencies = byte_frequencies(&[]);

        assert_eq!(build_huffman_tree(&frequencies), None);
    }

    #[test]
    fn repeated_single_byte_creates_leaf_with_total_frequency() {
        let frequencies = byte_frequencies(b"aaaa");
        let tree = build_huffman_tree(&frequencies).expect("single symbol should create a tree");

        assert_eq!(
            tree,
            HuffmanTree::Leaf {
                byte: b'a',
                frequency: 4
            }
        );
        assert_eq!(tree.frequency(), 4);
    }

    #[test]
    fn mixed_input_tree_root_frequency_matches_input_length() {
        let frequencies = byte_frequencies(b"banana");
        let tree = build_huffman_tree(&frequencies).expect("mixed input should create a tree");

        assert_eq!(tree.frequency(), 6);
        assert_eq!(tree.minimum_byte(), b'a');
    }

    #[test]
    fn equal_frequency_symbols_build_deterministic_tree() {
        let frequencies = byte_frequencies(b"abcd");
        let first_tree = build_huffman_tree(&frequencies).expect("input should create a tree");
        let second_tree = build_huffman_tree(&frequencies).expect("input should create a tree");

        assert_eq!(first_tree, second_tree);
        assert_eq!(
            first_tree,
            HuffmanTree::Branch {
                frequency: 4,
                minimum_byte: b'a',
                left: Box::new(HuffmanTree::Branch {
                    frequency: 2,
                    minimum_byte: b'a',
                    left: Box::new(HuffmanTree::Leaf {
                        byte: b'a',
                        frequency: 1
                    }),
                    right: Box::new(HuffmanTree::Leaf {
                        byte: b'b',
                        frequency: 1
                    })
                }),
                right: Box::new(HuffmanTree::Branch {
                    frequency: 2,
                    minimum_byte: b'c',
                    left: Box::new(HuffmanTree::Leaf {
                        byte: b'c',
                        frequency: 1
                    }),
                    right: Box::new(HuffmanTree::Leaf {
                        byte: b'd',
                        frequency: 1
                    })
                })
            }
        );
    }
}
