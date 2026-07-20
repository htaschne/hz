# Native Engine Developer Guide

Hz links a Rust static library into the macOS Swift application through a C ABI. The Rust backend now implements the single-layer Huffman codec and the Swift wrapper preserves the same recursive compression contract as the Swift reference engine.

## Directory Layout

```text
native/
├── module.modulemap
└── hz-native/
    ├── Cargo.toml
    ├── Cargo.lock
    ├── build.rs
    ├── include/
    │   └── hz_native.h
    └── src/
        ├── error.rs
        ├── ffi.rs
        ├── lib.rs
        └── huffman/
            ├── compress.rs
            ├── decompress.rs
            ├── archive.rs
            ├── bit_reader.rs
            ├── bit_writer.rs
            ├── codes.rs
            ├── frequency.rs
            ├── mod.rs
            ├── roadmap.rs
            └── tree.rs
```

Swift wrapper code lives in:

```text
hz/RustHuffmanEngine.swift
hz/NativeEngineError.swift
hz/CompressionEngineFactory.swift
```

## Build Commands

```bash
make native
make native-release
make native-test
make native-header
make native-clean
```

`make native-release` produces:

```text
native/hz-native/target/aarch64-apple-darwin/release/libhz_native.a
```

The current supported native target is Apple Silicon macOS, `aarch64-apple-darwin`. The scripts use `HZ_NATIVE_TARGET` internally so `x86_64-apple-darwin` or universal builds can be added later.

## Xcode Integration

The app target has a project-relative build phase:

```text
scripts/native/build.sh "$CONFIGURATION"
```

Swift imports the C ABI through:

```swift
import HzNative
```

The module map is committed at `native/module.modulemap` and points at `native/hz-native/include/hz_native.h`. Xcode uses project-relative include and library search paths. No user-specific absolute paths are required.

## ABI Rules

The C ABI is small and stable:

- `hz_native_abi_version`
- `hz_native_version_string`
- `hz_native_is_available`
- `hz_native_compress`
- `hz_native_decompress`
- `hz_native_result_free`

Only C-compatible types cross the boundary. Rust FFI structs and enums use `#[repr(C)]`. Do not expose Rust slices, `String`, `Vec`, trait objects, or Rust enums directly.

The checked-in header is manually maintained. Regenerate/validate explicitly with:

```bash
make native-header
```

If cbindgen is introduced later, keep the generated header committed so Xcode does not need to download tools during normal builds.

## Ownership Rules

- Input memory belongs to Swift or the C caller.
- Rust must not retain input pointers after an exported call returns.
- Output memory belongs to Rust.
- Swift copies output into owned `Data`.
- Swift must release Rust-owned output by passing the whole result to `hz_native_result_free`.
- Callers must not call `free()` on Rust-owned memory.
- Error strings currently point to static storage and are not released directly.
- `hz_native_result_free` accepts successful results, error results, empty buffers, and null buffers.
- A non-empty result is single-owner; freeing the same non-empty result twice is invalid.

## Panic Safety

No panic may unwind across the C ABI. Exported FFI calls are wrapped with `std::panic::catch_unwind` and unexpected panics become `HZ_NATIVE_INTERNAL_ERROR`.

Avoid `unwrap`, `expect`, unchecked indexing, and panic-prone code in exported paths. If an invariant is truly impossible to violate, keep the check close to the boundary and document it.

## Current Rust Behavior

The Rust Huffman entry points implement one `.hz` layer:

```text
src/huffman/compress.rs
src/huffman/decompress.rs
```

Compression:

- counts byte frequencies;
- builds the same deterministic Huffman tree as the Swift reference implementation;
- generates tree-path codes for archive payload compatibility;
- also builds canonical codes internally as a future interchange representation;
- writes the payload MSB-first with zero padding;
- serializes the Swift-compatible `HZF1` version 2 archive.

Decompression:

- parses and validates the `HZF1` version 2 archive;
- rebuilds the Huffman tree from the stored frequency table;
- reads only `encodedBitCount` meaningful bits;
- stops after `originalByteCount` output bytes;
- validates single-symbol archives by requiring every meaningful bit to be `0`.

Padding bits are never decoded as output. Invalid magic, unsupported versions or flags, truncated headers, malformed frequency tables, and payload length mismatches report `HZ_NATIVE_INVALID_ARGUMENT`.

The Swift reference engine remains the production default through `CompressionEngineFactory.defaultKind == .swift`. Selecting `.rust` uses the native single-layer codec through `RustHuffmanEngine`.

## Streaming APIs

The Rust crate exposes bounded-memory streaming primitives:

```rust
compress_stream<R, W>(input: &mut R, output: &mut W)
where
    R: Read + Seek,
    W: Write

decompress_stream<R, W>(input: &mut R, output: &mut W)
where
    R: Read,
    W: Write
```

Compression requires a seekable input because ordinary Huffman coding needs the complete frequency table before payload encoding. The compressor preserves the caller’s starting stream position, reads to EOF in bounded chunks, seeks back to the starting position, writes the complete header, then streams the encoded payload. Output does not need to be seekable.

The default stream buffer is 64 KiB. The bit writer retains at most one partial payload byte in addition to caller-provided writer buffering.

Streaming decompression parses the header incrementally, reconstructs the tree, reads payload bits incrementally, and writes decoded output through a bounded buffer. It supports non-seekable input.

File helpers are also available:

```rust
compress_file(source, destination)
decompress_file(source, destination)
```

They use buffered file I/O and write to a temporary file beside the destination before renaming it into place. On failure, the temporary destination is removed so callers do not receive a valid-looking partial output.

The C ABI exposes UTF-8 path wrappers:

```c
hz_native_compress_file(const char *source_path, const char *destination_path)
hz_native_decompress_file(const char *source_path, const char *destination_path)
```

These functions return status-only `HzNativeResult` values with empty buffers on success.

## Recursive Boundaries

Recursive/adaptive compression remains Swift-owned. `RustHuffmanEngine` calls the Rust C ABI for each individual layer, then uses Swift `HzArchive` parsing to set the outer recursive layer count exactly like `SwiftHuffmanEngine`.

Decompression follows the same boundary: Swift reads the outer archive layer count and invokes Rust once per layer. This keeps the C ABI small and makes a future native recursion implementation optional rather than required for engine replacement.

Native streaming currently covers single-layer file compression and decompression. Recursive streaming is not claimed: adaptive recursive compression still compares complete candidate archives in Swift memory. A future bounded recursive implementation should use temporary files for candidate layers and preserve the same acceptance rules.

## Compatibility

The archive format is shared with Swift:

- magic bytes: `HZF1`
- version: `2`
- flags: `0`
- recursive layer count: little-endian `UInt16`
- original byte count: little-endian `UInt64`
- encoded bit count: little-endian `UInt64`
- sorted frequency entries: byte plus little-endian `UInt64`
- payload: MSB-first Huffman bitstream padded with zero bits

Rust-generated archives are decoded by `SwiftHuffmanEngine`, and Swift-generated archives are decoded by `RustHuffmanEngine` in the test suite.

See `docs/ARCHIVE_FORMAT.md` for the full normative archive specification, byte layout, parser rules, and golden examples.

Do not change the C ABI unless the Swift wrapper and header are updated together. Preserve the `CompressionEngine` behavior expected by `SwiftHuffmanEngine` so engine selection remains a simple factory choice.

## Benchmarks

Swift reference engine:

```bash
benchmarks/run.sh --engine swift --adaptive
```

Rust native engine:

```bash
benchmarks/run.sh --engine rust --max-depth 0
```

Rust mode builds the native static library, compiles the benchmark runner with `HZ_NATIVE_BRIDGE`, runs compression/decompression through `RustHuffmanEngine`, verifies the output, and emits the same CSV rows as Swift mode.
