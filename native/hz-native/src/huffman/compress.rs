use crate::error::NativeError;

use super::codes::{code_lengths, make_canonical_code_table, make_tree_code_table};
use super::frequency::byte_frequencies;
use super::frequency::total_frequency;
use super::tree::build_huffman_tree;

pub fn compress(input: &[u8]) -> Result<Vec<u8>, NativeError> {
    let frequencies = byte_frequencies(input);
    debug_assert_eq!(total_frequency(&frequencies), input.len() as u64);

    let tree = build_huffman_tree(&frequencies);

    if let Some(tree) = &tree {
        debug_assert_eq!(tree.frequency(), input.len() as u64);

        let code_table = make_tree_code_table(tree)?;
        debug_assert!(code_table.iter().any(Option::is_some));
        debug_assert!(code_table
            .iter()
            .flatten()
            .all(|code| code.bit_len() == code.bits().len()));

        let lengths = code_lengths(tree);
        let canonical_table = make_canonical_code_table(&lengths)?;
        debug_assert_eq!(
            code_table.iter().filter(|code| code.is_some()).count(),
            canonical_table.iter().filter(|code| code.is_some()).count()
        );
    }

    // TODO(native-huffman): implement bit writer, archive serialization, and
    // recursive compression boundaries.
    Err(NativeError::NotImplemented(
        "Rust Huffman compression is not implemented yet",
    ))
}
