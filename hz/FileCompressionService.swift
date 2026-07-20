//
//  FileCompressionService.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct FileCompressionService {
    let engine: CompressionEngine

    init(engine: CompressionEngine = CompressionEngineFactory.make()) {
        self.engine = engine
    }

    func compressFile(
        at url: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws -> Data {
        onProgress("Reading file...", 0.1)
        let input = try Data(contentsOf: url)

        onProgress("Compressing recursively...", 0.35)
        let result = try engine.compress(input, options: .adaptive)

        onProgress("Compression complete after \(result.acceptedLayerCount) layer(s).", 1.0)
        return result.archive
    }

    func compressFile(
        at sourceURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws {
        if let rustEngine = engine as? RustHuffmanEngine {
            onProgress("Compressing with native streaming backend...", -1)
            try rustEngine.compressFile(at: sourceURL, to: destinationURL)
            onProgress("Compression complete.", 1.0)
            return
        }

        let archive = try compressFile(at: sourceURL, onProgress: onProgress)
        try archive.write(to: destinationURL)
    }

    func decompressFile(
        at url: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws -> Data {
        onProgress("Reading archive...", 0.1)
        let archive = try Data(contentsOf: url)

        onProgress("Decompressing file...", 0.35)
        let output = try engine.decompress(archive, options: .full)

        onProgress("Decompression complete.", 1.0)
        return output
    }

    func decompressFile(
        at sourceURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws {
        if let rustEngine = engine as? RustHuffmanEngine {
            onProgress("Decompressing with native streaming backend...", -1)
            try rustEngine.decompressFile(at: sourceURL, to: destinationURL)
            onProgress("Decompression complete.", 1.0)
            return
        }

        let output = try decompressFile(at: sourceURL, onProgress: onProgress)
        try output.write(to: destinationURL)
    }
}
