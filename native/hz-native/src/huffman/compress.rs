use crate::error::NativeError;

use std::cmp::Reverse;
use std::collections::BinaryHeap;

pub fn compress(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    let frequencies = byte_frequencies(input);
    let tree = build_huffman_tree(&frequencies);

    if let Some(tree) = &tree {
        debug_assert_eq!(tree.frequency(), input.len());
        debug_assert!(tree.lowest_byte().is_some());
    }

    // TODO(native-huffman): implement the future compression pipeline with
    // code generation, bit writer, archive serialization, and recursive
    // compression boundaries.
    Err(NativeError::NotImplemented(
        "Rust Huffman compression is not implemented yet",
    ))
}

#[derive(Debug, Eq, PartialEq)]
enum HuffmanTree {
    Leaf {
        byte: u8,
        frequency: usize,
    },
    Branch {
        frequency: usize,
        left: Box<HuffmanTree>,
        right: Box<HuffmanTree>,
    },
}

impl HuffmanTree {
    fn frequency(&self) -> usize {
        match self {
            Self::Leaf { frequency, .. } | Self::Branch { frequency, .. } => *frequency,
        }
    }

    fn lowest_byte(&self) -> Option<u8> {
        match self {
            Self::Leaf { byte, .. } => Some(*byte),
            Self::Branch { left, right, .. } => left.lowest_byte().min(right.lowest_byte()),
        }
    }
}

#[derive(Debug)]
struct HeapEntry {
    frequency: usize,
    sequence: usize,
    tree: HuffmanTree,
}

impl PartialEq for HeapEntry {
    fn eq(&self, other: &Self) -> bool {
        self.frequency == other.frequency && self.sequence == other.sequence
    }
}

impl Eq for HeapEntry {}

impl PartialOrd for HeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for HeapEntry {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.frequency
            .cmp(&other.frequency)
            .then_with(|| self.sequence.cmp(&other.sequence))
    }
}

fn byte_frequencies(input: &[u8]) -> [usize; 256] {
    let mut frequencies = [0; 256];

    for &byte in input {
        frequencies[usize::from(byte)] += 1;
    }

    frequencies
}

fn build_huffman_tree(frequencies: &[usize; 256]) -> Option<HuffmanTree> {
    let mut heap = BinaryHeap::new();
    let mut next_sequence = 0;

    for (byte, &frequency) in frequencies.iter().enumerate() {
        if frequency == 0 {
            continue;
        }

        heap.push(Reverse(HeapEntry {
            frequency,
            sequence: next_sequence,
            tree: HuffmanTree::Leaf {
                byte: byte as u8,
                frequency,
            },
        }));
        next_sequence += 1;
    }

    while heap.len() > 1 {
        let Reverse(left) = heap
            .pop()
            .expect("heap length was checked before popping left child");
        let Reverse(right) = heap
            .pop()
            .expect("heap length was checked before popping right child");
        let frequency = left.frequency + right.frequency;

        heap.push(Reverse(HeapEntry {
            frequency,
            sequence: next_sequence,
            tree: HuffmanTree::Branch {
                frequency,
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

    #[derive(Debug, Eq, PartialEq)]
    enum TreeShape {
        Leaf(u8, usize),
        Branch(usize, Box<TreeShape>, Box<TreeShape>),
    }

    fn tree_shape(tree: &HuffmanTree) -> TreeShape {
        match tree {
            HuffmanTree::Leaf { byte, frequency } => TreeShape::Leaf(*byte, *frequency),
            HuffmanTree::Branch {
                frequency,
                left,
                right,
            } => TreeShape::Branch(
                *frequency,
                Box::new(tree_shape(left)),
                Box::new(tree_shape(right)),
            ),
        }
    }

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
    fn mixed_input_counts_raw_bytes() {
        let frequencies = byte_frequencies(b"banana");

        assert_eq!(frequencies[usize::from(b'b')], 1);
        assert_eq!(frequencies[usize::from(b'a')], 3);
        assert_eq!(frequencies[usize::from(b'n')], 2);
    }

    #[test]
    fn mixed_input_tree_root_frequency_matches_input_length() {
        let frequencies = byte_frequencies(b"banana");
        let tree = build_huffman_tree(&frequencies).expect("mixed input should create a tree");

        assert_eq!(tree.frequency(), 6);
    }

    #[test]
    fn equal_frequency_symbols_build_deterministic_tree() {
        let frequencies = byte_frequencies(b"abcd");
        let first_tree = build_huffman_tree(&frequencies).expect("input should create a tree");
        let second_tree = build_huffman_tree(&frequencies).expect("input should create a tree");

        assert_eq!(tree_shape(&first_tree), tree_shape(&second_tree));
        assert_eq!(
            tree_shape(&first_tree),
            TreeShape::Branch(
                4,
                Box::new(TreeShape::Branch(
                    2,
                    Box::new(TreeShape::Leaf(b'a', 1)),
                    Box::new(TreeShape::Leaf(b'b', 1))
                )),
                Box::new(TreeShape::Branch(
                    2,
                    Box::new(TreeShape::Leaf(b'c', 1)),
                    Box::new(TreeShape::Leaf(b'd', 1))
                ))
            )
        );
    }
}
