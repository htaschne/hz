<p align="center">
  <img src="https://raw.githubusercontent.com/htaschne/hz/refs/heads/main/hz/Assets.xcassets/AppIcon.appiconset/512.png" alt="Hz icon"/>
</p>

# Hz

A small Huffman compression tool built with Swift and SwiftUI.

Originally created as an educational project, Hz is being rebuilt with a focus on clean architecture, correctness, and native interoperability. The long-term goal is to keep the macOS interface in SwiftUI while moving the compression engine to a low-level implementation exposed through a C ABI.

## Features

- Huffman compression and decompression
- Native macOS drag-and-drop interface
- Custom `.hz` archive format
- Modular compression pipeline
- Designed for future native engine integration

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

The Swift implementation acts as the reference implementation. Future versions will replace the compression engine with a native implementation while preserving the same public interface.

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

## Building

```bash
git clone https://github.com/htaschne/hz.git
cd hz
open hz.xcodeproj
```

## Demo

While Huffman coding is primarily an educational algorithm today, Hz can still compress the Bible in under a second and decompress it in roughly two seconds on modern hardware.

<p align="center">
  <img src="https://raw.githubusercontent.com/htaschne/hz/refs/heads/main/media/hz-demo.gif" alt="Gif of Hz app demo"/>
</p>

## Roadmap

- [x] Reference Huffman implementation in Swift
- [x] Modular archive format
- [x] Unit tests
- [ ] Native compression engine (Rust/C/C++/Zig)
- [ ] C ABI bridge
- [ ] Performance benchmarks
- [ ] Streaming compression
- [ ] Archive format specification

## Why?

Most compression projects either focus on algorithms or user interfaces. Hz aims to explore both: a modern macOS application backed by a compression engine that can evolve independently from the UI.

## License

MIT
