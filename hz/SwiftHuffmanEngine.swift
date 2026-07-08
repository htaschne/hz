//
//  SwiftHuffmanEngine.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct SwiftHuffmanEngine: CompressionEngine {
    private let codec = HuffmanCodec()

    func compress(_ input: Data) throws -> Data {
        try codec.encode(input).serialize()
    }

    func decompress(_ archive: Data) throws -> Data {
        let parsedArchive = try HzArchive.parse(archive)
        return try codec.decode(parsedArchive)
    }
}

