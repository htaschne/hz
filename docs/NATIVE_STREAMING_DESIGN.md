# Native Streaming Design Note

This note records the audit decisions behind the bounded-memory native streaming implementation.

## Previous Behavior

- Swift file workflows read full source files into `Data` and returned full archive/output `Data`.
- Rust C ABI functions accepted full input buffers and returned full output buffers.
- Rust compression built a complete encoded payload `Vec<u8>` before archive serialization.
- Rust decompression parsed the complete archive and returned a complete decoded `Vec<u8>`.

## Archive Constraints

The current `HZF1` version 2 archive stores:

- original byte count;
- encoded bit count;
- full frequency table;
- packed payload.

No footer exists, and the layout must not change. Because the encoded bit count can be calculated from the frequency table and tree-path code lengths, the compressor can know every header field after a first frequency-counting pass. Therefore the output does not need to be seekable and no header patching is required.

## Streaming Compression

Single-layer streaming compression uses two passes over `Read + Seek` input:

1. record the current input position;
2. read bounded chunks to count frequencies and original length;
3. seek back to the recorded position;
4. build the same deterministic Huffman tree used by the in-memory codec;
5. compute `encodedBitCount` from frequencies and code lengths;
6. write the archive header;
7. reread bounded chunks and stream encoded bits directly to `Write`.

The default chunk buffer is 64 KiB. The bit writer retains at most one partial payload byte.

Non-seekable compression is not claimed. It would require spooling the source to a temporary file or a different archive design.

## Streaming Decompression

Streaming decompression accepts non-seekable `Read` input:

1. parse fixed and variable header fields incrementally;
2. reconstruct the tree from the frequency table;
3. read payload bytes as needed;
4. emit decoded bytes through a bounded output buffer;
5. enforce `originalByteCount` and `encodedBitCount`.

Padding bits are not decoded as output. Current v2 decoders ignore padding bit values rather than treating nonzero padding as an integrity failure.

## File APIs

Rust file helpers use `BufReader` and `BufWriter`. Destinations are written to a temporary file next to the final path and renamed into place only after success. Failed operations remove the temporary file.

The C ABI exposes UTF-8 path wrappers around those helpers. Buffer-based ABI functions remain available and intentionally remain in-memory.

## Recursive Compression

Recursive/adaptive compression is still Swift-owned and in-memory. Adaptive mode compares complete candidate archives before accepting or rejecting a layer. This implementation does not claim bounded-memory recursive compression.

A future recursive streaming implementation should use temporary files for candidate layers and compare file sizes without weakening the existing acceptance rules.
