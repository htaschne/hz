<p align="center">
  <img src="https://raw.githubusercontent.com/htaschne/hz/refs/heads/main/hz/Assets.xcassets/AppIcon.appiconset/512.png" alt="Hz icon"/>
</p>

# Hz

A small Huffman compression tool built with Swift and SwiftUI.

Originally created as an educational project, Hz is being rebuilt with a focus on clean architecture, correctness, and native interoperability. The long-term goal is to keep the macOS interface in SwiftUI while moving the compression engine to a low-level implementation exposed through a C ABI.

## Features

- Huffman compression and decompression
- Adaptive recursive Huffman compression
- Native macOS drag-and-drop interface
- Custom `.hz` archive format
- Modular compression pipeline
- Rust native-engine bridge through a C ABI

## Architecture

The project is organized into small, focused components.

```text
Hz/
├── App/              SwiftUI application
├── Core/
│   ├── HuffmanTree
│   ├── HuffmanCodec
│   ├── BitReader
│   ├── BitWriter
│   ├── FrequencyTable
│   └── HzArchive
└── Tests/
```

The Swift implementation acts as the working reference implementation. The repository also contains a Rust static library linked through a small C ABI. That Rust bridge is callable from Swift, but Rust Huffman compression and decompression are intentionally not implemented yet.

```text
SwiftUI
   ↓
FileCompressionService
   ↓
CompressionEngine
   ├── SwiftHuffmanEngine
   └── RustHuffmanEngine
            ↓
          C ABI
            ↓
       hz-native Rust crate
            ↓
      Huffman pipeline TODO
```

## The `.hz` Format

Each archive is composed of three logical sections:

```text
┌────────────────────┬──────────────────────────┬───────────┐
│ Header             │ Encoded Huffman Payload  │ Padding   │
├────────────────────┼──────────────────────────┼───────────┤
│ 010101...          │ 1011010011010...         │ 000000    │
└────────────────────┴──────────────────────────┴───────────┘
```

The header stores the metadata required to reconstruct the Huffman tree and decode the payload safely.

It includes:

- magic identifier
- format version
- original file size
- encoded bit count
- Huffman metadata

The payload contains the packed Huffman bitstream. The optional padding aligns the stream to a full byte and is ignored during decoding using the stored bit count.

Current archives use format version 2. The header also stores flags and an outer-only recursive layer count. Inner recursive layers write a layer count of `0`; only the outermost archive records how many Huffman layers must be removed to recover the original bytes.

## Recursive Compression

Hz can recursively compress the output of a previous Huffman pass:

```text
original
   ↓
layer 1 `.hz`
   ↓
layer 2 `.hz`
   ↓
layer 3 `.hz`
```

Normal application compression uses adaptive mode:

- always perform the first Huffman pass
- continue while the next archive is strictly smaller
- stop before a non-improving layer
- discard the non-improving candidate
- record the accepted layer count in the outermost archive

Depth uses benchmark-oriented semantics:

- `maxDepth = 0` means traditional single-pass compression
- `maxDepth = 1` allows at most two total Huffman layers
- `maxDepth = 2` allows at most three total Huffman layers

Full decompression unwraps all layers recorded by the outermost archive. Partial decompression can remove only the requested number of outer layers and return a remaining valid `.hz` archive.

Recursive Huffman compression is an experiment and benchmark feature, not a claim that repeated Huffman coding generally improves compression. High-entropy and already-compressed-like inputs usually grow.

## Benchmarks

The benchmark runner lives in `benchmarks/` and compiles the production Swift reference engine with `swiftc -O`.

Baseline single-pass run:

```bash
benchmarks/run.sh --max-depth 0
```

Explicit Swift engine run:

```bash
benchmarks/run.sh --engine swift --max-depth 0
```

Adaptive recursive run:

```bash
benchmarks/run.sh --adaptive
```

Forced recursive run:

```bash
benchmarks/run.sh --max-depth 3
```

Native Rust bridge probe:

```bash
benchmarks/run.sh --engine rust
```

The Rust benchmark mode builds and calls the native bridge, reports that the bridge is available, then exits with a nonzero status because Rust Huffman compression is not implemented. It does not write benchmark CSV rows for the unimplemented engine.

Analyze generated CSV files:

```bash
benchmarks/analyze.py
```

Results are written under `benchmarks/results/`. Generated raw archives and CSV files are ignored by git.

## Building

```bash
git clone https://github.com/htaschne/hz.git
cd hz
open hz.xcodeproj
```

Native build commands:

```bash
make native
make native-release
make native-test
make native-header
make native-clean
```

The Xcode app target builds `native/hz-native` before Swift links. The checked-in C header is `native/hz-native/include/hz_native.h`, and Swift imports it through `native/module.modulemap`. The current native target is Apple Silicon macOS: `aarch64-apple-darwin`.

Native ownership rules are intentionally simple: Swift owns input `Data`, Rust never retains input pointers, Rust owns returned buffers, and Swift releases those buffers by calling `hz_native_result_free` through `RustHuffmanEngine`.

See `docs/NATIVE_ENGINE.md` for ABI rules and the future Rust implementation roadmap.

## Demo

While Huffman coding is primarily an educational algorithm today, Hz can still compress the Bible in under a second and decompress it in roughly two seconds on modern hardware.

<p align="center">
  <img src="https://raw.githubusercontent.com/htaschne/hz/refs/heads/main/media/hz-demo.gif" alt="Gif of Hz app demo"/>
</p>

## Roadmap

- [x] Reference Huffman implementation in Swift
- [x] Modular archive format
- [x] Unit tests
- [x] Recursive benchmark harness
- [x] C ABI bridge
- [x] Rust native-engine scaffold
- [ ] Rust Huffman implementation
- [ ] Streaming compression
- [ ] Archive format specification

## Why?

Most compression projects either focus on algorithms or user interfaces. Hz aims to explore both: a modern macOS application backed by a compression engine that can evolve independently from the UI.

## License

MIT
