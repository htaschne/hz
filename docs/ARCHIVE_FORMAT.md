# Hz Archive Format

This document is the normative specification for the current `.hz` archive format. It describes the existing format implemented by the Swift reference engine and the Rust native engine. It does not define a replacement format.

## Identity

- File extension: `.hz`
- Magic bytes: ASCII `HZF1` (`48 5A 46 31`)
- Current format version: `2`
- Byte order: little-endian for every multi-byte integer
- Integrity checksum: none

Decoders MUST reject archives whose magic bytes are not `HZF1`. Version `1` and non-`HZF1` legacy data are unsupported by the current implementation. Decoders MUST reject versions other than `2`.

## Top-Level Layout

| Offset | Size | Field | Encoding | Description |
|---:|---:|---|---|---|
| 0 | 4 | magic | ASCII bytes | MUST be `HZF1`. |
| 4 | 1 | version | `UInt8` | MUST be `2`. |
| 5 | 1 | flags | `UInt8` | MUST be `0`; all bits are reserved. |
| 6 | 2 | recursiveLayerCount | `UInt16LE` | Total accepted layer count on the outermost recursive archive. `0` means no advertised recursion depth. |
| 8 | 8 | originalByteCount | `UInt64LE` | Number of bytes represented by this archive layer before Huffman encoding. |
| 16 | 8 | encodedBitCount | `UInt64LE` | Number of meaningful bits in the encoded payload, excluding final-byte padding. |
| 24 | 2 | frequencyEntryCount | `UInt16LE` | Number of frequency entries that follow. |
| 26 | `9 * frequencyEntryCount` | frequency table | repeated entry | Sorted by symbol byte in ascending order. |
| `26 + 9N` | `ceil(encodedBitCount / 8)` | payload | packed bits | Huffman bitstream, MSB-first within each byte. |

Frequency entry layout:

| Relative Offset | Size | Field | Encoding | Description |
|---:|---:|---|---|---|
| 0 | 1 | symbol | `UInt8` | Byte value. |
| 1 | 8 | frequency | `UInt64LE` | Occurrence count in the uncompressed input for this layer. MUST be greater than `0`. |

Let `N = frequencyEntryCount`.

Payload offset:

```text
payloadOffset = 26 + 9 * N
payloadByteCount = encodedBitCount / 8 + (encodedBitCount % 8 == 0 ? 0 : 1)
archiveByteCount = payloadOffset + payloadByteCount
```

Trailing bytes are not allowed. A parser MUST reject an archive if the bytes remaining after the frequency table are not exactly `payloadByteCount`.

## Huffman Metadata

Version 2 stores a frequency table, not a canonical code table.

Canonical Huffman metadata fields, symbol code lengths, and serialized canonical codes are absent from this format. Compatible encoders and decoders MUST reconstruct the deterministic Huffman tree from the stored frequency table.

The implementation also contains canonical-code generation for future use, but canonical codes are not used to encode or decode version 2 payloads. An independent v2 decoder that uses canonical codes instead of the tree reconstruction below will not be compatible.

## Tree Reconstruction

For each frequency entry, create a leaf node containing:

- `symbol`
- `frequency`
- `minimumByte = symbol`

Build the tree by repeatedly combining the two highest-priority nodes until one root remains.

Priority order:

1. lower `frequency` first;
2. if frequencies are equal, lower `minimumByte` first.

The first popped node becomes the left child. The second popped node becomes the right child. A parent node has:

```text
frequency = left.frequency + right.frequency
minimumByte = min(left.minimumByte, right.minimumByte)
```

Codes are assigned by walking the tree:

- left edge: bit `0`
- right edge: bit `1`
- leaf code: path bits from root to leaf
- single-symbol tree: code is one bit, `0`

## Payload Bit Order and Padding

Payload bits are packed most-significant-bit first in each byte.

For bit index `i` in the encoded stream:

```text
byteIndex = i / 8
shift = 7 - (i % 8)
bit = (payload[byteIndex] >> shift) & 1
```

Only `encodedBitCount` bits are meaningful. Encoders pad the final byte with zero bits when `encodedBitCount` is not byte-aligned. Decoders MUST NOT let padding bits produce output. Current decoders ignore padding bit values rather than treating nonzero padding as an integrity error.

## Empty Input

An empty archive layer is represented as:

- `originalByteCount = 0`
- `encodedBitCount = 0`
- `frequencyEntryCount = 0`
- no payload bytes

## Single-Symbol Input

For an input containing one distinct byte:

- the tree is a single leaf;
- that byte’s code is `0`;
- `encodedBitCount == originalByteCount`;
- every meaningful payload bit MUST be `0`;
- decoders MUST reject a single-symbol archive containing any meaningful `1` bit.

## Recursive Archives

Recursive compression wraps complete `.hz` archives as the input to later Huffman layers.

Layer ordering:

```text
original bytes
  -> inner layer 1 archive
  -> layer 2 archive
  -> ...
  -> outermost archive
```

The outermost archive records the total accepted layer count in `recursiveLayerCount`. Inner layers write `recursiveLayerCount = 0` so they remain independently decodable as single-layer archives.

If `recursiveLayerCount == 0`, decoders treat the archive as one layer. If it is nonzero, full recursive decompression removes exactly that many layers.

Adaptive compression behavior is not stored beyond the accepted layer count:

- the first layer is always accepted;
- a candidate next layer is accepted only if adaptive mode allows it;
- rejected candidate layers are discarded and are not serialized;
- only the accepted layer count is recorded in the outermost archive.

## Malformed Archive Rules

Decoders MUST reject:

- fewer than 26 bytes before the payload;
- invalid magic bytes;
- unsupported version;
- nonzero flags;
- `recursiveLayerCount == 0`, `originalByteCount == 0`, and `encodedBitCount != 0`;
- duplicate frequency entries;
- frequency entries with value `0`;
- frequency total not equal to `originalByteCount`;
- empty input with non-empty frequencies or nonzero encoded bits;
- non-empty input with zero frequencies or zero encoded bits;
- payload length different from `ceil(encodedBitCount / 8)`;
- truncated payload;
- bitstreams that cannot produce exactly `originalByteCount` decoded bytes;
- single-symbol payloads whose meaningful bits are not all `0`.

Maximum supported values are bounded by serialized field widths and host allocation limits:

- `recursiveLayerCount`: `UInt16`
- `originalByteCount`: `UInt64`
- `encodedBitCount`: `UInt64`
- `frequencyEntryCount`: at most 256 valid byte symbols, although the field is `UInt16`
- payload byte count: `ceil(encodedBitCount / 8)` and must fit in the host decoder’s addressable range for in-memory APIs

Forward compatibility rule: a decoder for version 2 MUST reject nonzero flags and unknown versions. New semantics require a new version or explicitly defined flags.

## Pseudocode

### Serialize One Archive Layer

```text
frequencies = count bytes in input
originalByteCount = sum(frequencies)

if originalByteCount == 0:
    encodedBitCount = 0
    payload = []
else:
    tree = buildTree(frequencies)
    codes = assignTreePathCodes(tree)
    encodedBitCount = sum(frequencies[symbol] * bitLength(codes[symbol]))
    payload = pack input bytes through codes, MSB-first
    pad final payload byte with zero bits

write "HZF1"
write UInt8(2)
write UInt8(0)
write UInt16LE(recursiveLayerCount)
write UInt64LE(originalByteCount)
write UInt64LE(encodedBitCount)
write UInt16LE(number of nonzero frequency entries)
for symbol in ascending byte order:
    if frequencies[symbol] > 0:
        write UInt8(symbol)
        write UInt64LE(frequencies[symbol])
write payload
```

### Parse One Archive Layer

```text
read fixed header
validate magic, version, flags
read N frequency entries
reject duplicate symbols or zero frequencies
verify sum(frequencies) == originalByteCount
payloadByteCount = ceil(encodedBitCount / 8)
read exactly payloadByteCount bytes
reject any trailing bytes
```

### Reconstruct Canonical Huffman Codes

Canonical codes are not serialized and are not used for v2 payload decoding. If a future tool needs a canonical table from the reconstructed tree, it can derive code lengths and assign canonical codes:

```text
lengths = [(symbol, treePathLength(symbol)) for every leaf]
sort lengths by (bitLength, symbol)
code = 0
previousLength = 0
for (symbol, bitLength) in lengths:
    if previousLength == 0:
        code = 0 with bitLength bits
    else:
        code = code + 1
        code = code << (bitLength - previousLength)
    canonicalCode[symbol] = code represented with bitLength bits
    previousLength = bitLength
```

Again, v2 payloads MUST be decoded with tree-path codes reconstructed from frequencies.

### Decode Payload

```text
if originalByteCount == 0:
    return []

tree = buildTree(frequencies)

if tree is single leaf:
    require encodedBitCount == originalByteCount
    for each meaningful bit:
        require bit == 0
    return leaf.symbol repeated originalByteCount times

output = []
node = tree.root
for i in 0..<encodedBitCount:
    bit = read payload bit i, MSB-first
    node = bit == 0 ? node.left : node.right
    if node is leaf:
        append node.symbol to output
        if output.count == originalByteCount:
            return output
        node = tree.root

reject archive because decoded output ended early
```

### Recursive Unwrap

```text
outer = parse archive
layerCount = outer.recursiveLayerCount == 0 ? 1 : outer.recursiveLayerCount
currentBytes = serialized outer archive

repeat layerCount times:
    archive = parse currentBytes
    currentBytes = decode one archive layer

return currentBytes
```

## Annotated Examples

All examples were generated by the Rust implementation and locked by golden fixture tests.

### Empty Input

Input: empty byte string.

```text
48 5A 46 31 02 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00
```

Fields:

- magic `HZF1`
- version `2`
- flags `0`
- recursive layer count `0`
- original byte count `0`
- encoded bit count `0`
- frequency entry count `0`
- payload empty

### Single Symbol

Input: `aaaa`.

```text
48 5A 46 31 02 00 00 00 04 00 00 00 00 00 00 00
04 00 00 00 00 00 00 00 01 00 61 04 00 00 00 00
00 00 00 00
```

Fields:

- original byte count `4`
- encoded bit count `4`
- one frequency entry: symbol `0x61` (`a`), frequency `4`
- payload byte `00`; the four meaningful bits are `0000`

### Mixed Input

Input: `banana`.

```text
48 5A 46 31 02 00 00 00 06 00 00 00 00 00 00 00
09 00 00 00 00 00 00 00 03 00 61 03 00 00 00 00
00 00 00 62 01 00 00 00 00 00 00 00 6E 02 00 00
00 00 00 00 00 9B 00
```

Fields:

- original byte count `6`
- encoded bit count `9`
- frequency entries:
  - `0x61` (`a`): `3`
  - `0x62` (`b`): `1`
  - `0x6E` (`n`): `2`
- payload bytes `9B 00`
- meaningful bits: `100110110`
- final padding bits: seven zero bits
