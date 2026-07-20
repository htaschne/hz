//! Component map for the Rust Huffman implementation.
//!
//! This module intentionally contains no compression logic. The implemented
//! component boundaries are:
//!
//! - frequency table: count byte frequencies for one input layer;
//! - tree construction: build the Huffman tree from byte frequencies;
//! - code generation: derive tree-path prefix codes and canonical codes;
//! - bit writer: pack variable-length codes into bytes;
//! - bit reader: read encoded payload bits without consuming padding;
//! - archive serialization: write the versioned `.hz` archive format;
//! - archive parsing: validate headers and payload boundaries;
//! - Swift recursive compression: apply adaptive or forced-depth layering;
//! - Swift recursive decompression: unwrap recorded archive layers through the
//!   native single-layer decoder.
