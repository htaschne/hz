//
//  FileCompressionService.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct FileCompressionService {
    let engine: CompressionEngine

    init(engine: CompressionEngine = SwiftHuffmanEngine()) {
        self.engine = engine
    }

    func compressFile(
        at url: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws -> Data {
        onProgress("Reading file...", 0.1)
        let input = try Data(contentsOf: url)

        onProgress("Compressing file...", 0.35)
        let archive = try engine.compress(input)

        onProgress("Compression complete.", 1.0)
        return archive
    }

    func decompressFile(
        at url: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws -> Data {
        onProgress("Reading archive...", 0.1)
        let archive = try Data(contentsOf: url)

        onProgress("Decompressing file...", 0.35)
        let output = try engine.decompress(archive)

        onProgress("Decompression complete.", 1.0)
        return output
    }
}

