//
//  HuffmanCodec.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

enum HuffmanCodecError: Error {
    case missingCode(UInt8)
    case missingTree
}

struct HuffmanCodec {
    func encode(_ input: Data) throws -> HzArchive {
        let frequencies = FrequencyTable.make(from: input)

        guard let tree = HuffmanTree.build(frequencies: frequencies) else {
            return HzArchive(
                flags: HzArchive.supportedFlags,
                recursiveLayerCount: 0,
                originalByteCount: 0,
                encodedBitCount: 0,
                frequencies: [:],
                payload: Data()
            )
        }

        let codes = tree.makeCodeTable()
        var writer = BitWriter()

        for byte in input {
            guard let code = codes[byte] else {
                throw HuffmanCodecError.missingCode(byte)
            }

            writer.writeBits(code)
        }

        return HzArchive(
            flags: HzArchive.supportedFlags,
            recursiveLayerCount: 0,
            originalByteCount: UInt64(input.count),
            encodedBitCount: writer.bitCount,
            frequencies: frequencies,
            payload: writer.finish()
        )
    }

    func decode(_ archive: HzArchive) throws -> Data {
        guard archive.originalByteCount > 0 else {
            return Data()
        }

        guard let tree = HuffmanTree.build(frequencies: archive.frequencies) else {
            throw HuffmanCodecError.missingTree
        }

        return try tree.decode(
            payload: archive.payload,
            encodedBitCount: archive.encodedBitCount,
            originalByteCount: archive.originalByteCount
        )
    }
}
