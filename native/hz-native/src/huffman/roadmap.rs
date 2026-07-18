//! Roadmap for the future Rust Huffman implementation.
//!
//! This module intentionally contains no compression logic. The planned
//! component boundaries are:
//!
//! - frequency table: count byte frequencies for one input layer;
//! - tree construction: build the Huffman tree from byte frequencies;
//! - code generation: derive prefix codes from the tree;
//! - bit writer: pack variable-length codes into bytes;
//! - bit reader: read encoded payload bits without consuming padding;
//! - archive serialization: write the versioned `.hz` archive format;
//! - archive parsing: validate headers and payload boundaries;
//! - recursive compression: apply adaptive or forced-depth layering;
//! - recursive decompression: unwrap recorded archive layers.
