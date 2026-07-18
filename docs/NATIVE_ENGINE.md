# Native Engine Developer Guide

Hz now links a Rust static library into the macOS Swift application through a C ABI. The native engine is infrastructure only: the Rust Huffman compression and decompression pipeline is intentionally unimplemented.

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
            ├── mod.rs
            └── roadmap.rs
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

The Rust Huffman entry points are stubs:

```text
src/huffman/compress.rs
src/huffman/decompress.rs
```

They return:

```text
HZ_NATIVE_NOT_IMPLEMENTED
```

with a stable message. This is intentional. The Swift reference engine remains the production default.

## Future Huffman Pipeline

Implement the Rust engine behind these component boundaries:

- frequency table
- tree construction
- code generation
- bit writer
- bit reader
- archive serialization
- archive parsing
- recursive compression
- recursive decompression

Do not change the C ABI unless the Swift wrapper and header are updated together. Preserve the `CompressionEngine` behavior expected by `SwiftHuffmanEngine` so engine selection remains a simple factory choice.

## Benchmarks

Swift reference engine:

```bash
benchmarks/run.sh --engine swift --adaptive
```

Rust bridge probe:

```bash
benchmarks/run.sh --engine rust
```

Rust mode currently builds and calls the bridge, reports availability, then exits with code `2` and a not-implemented message. It does not emit CSV benchmark rows until the Rust Huffman pipeline exists.
