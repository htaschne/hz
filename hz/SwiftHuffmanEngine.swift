//
//  SwiftHuffmanEngine.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct SwiftHuffmanEngine: CompressionEngine {
    static let maximumAdditionalDepth = 32

    private let codec = HuffmanCodec()

    func compress(_ input: Data, options: CompressionOptions) throws -> CompressionResult {
        let run = try RecursiveCompressionController.run(
            input: input,
            options: options,
            maximumAdditionalDepth: Self.maximumAdditionalDepth
        ) { input in
            try makeLayerArchive(from: input, recursiveLayerCount: 0)
        }

        return try makeResult(from: run)
    }

    func decompress(_ archive: Data, options: DecompressionOptions) throws -> Data {
        let outerArchive = try HzArchive.parse(archive)
        let recordedLayerCount = Int(outerArchive.recursiveLayerCount == 0 ? 1 : outerArchive.recursiveLayerCount)

        guard recordedLayerCount > 0 else {
            throw CompressionEngineError.invalidRecordedLayerCount(outerArchive.recursiveLayerCount)
        }

        let layersToRemove = options.maxAdditionalDepth
            .map { min($0 + 1, recordedLayerCount) }
            ?? recordedLayerCount

        var currentArchive = outerArchive
        var currentBytes = archive

        for layerIndex in 1...layersToRemove {
            currentBytes = try codec.decode(currentArchive)

            if layerIndex < layersToRemove {
                guard currentBytes.starts(with: HzArchive.magic) else {
                    throw CompressionEngineError.missingNestedArchive(expectedLayer: layerIndex + 1)
                }

                currentArchive = try HzArchive.parse(currentBytes)
            }
        }

        if layersToRemove < recordedLayerCount {
            return currentBytes
        }

        return currentBytes
    }

    private func makeLayerArchive(from input: Data, recursiveLayerCount: UInt16) throws -> Data {
        try codec.encode(input)
            .withRecursiveLayerCount(recursiveLayerCount)
            .serialize()
    }

    private func makeResult(from run: RecursiveCompressionRun) throws -> CompressionResult {
        guard let parsedArchive = try? HzArchive.parse(run.archive) else {
            throw CompressionEngineError.emptyCompressionPasses
        }

        guard run.acceptedLayerCount <= Int(UInt16.max) else {
            throw CompressionEngineError.maximumDepthExceedsSafetyLimit(
                maximum: Self.maximumAdditionalDepth
            )
        }

        let finalArchive = try parsedArchive
            .withRecursiveLayerCount(UInt16(run.acceptedLayerCount))
            .serialize()

        return CompressionResult(
            archive: finalArchive,
            acceptedLayerCount: run.acceptedLayerCount,
            stoppingReason: run.stoppingReason,
            passes: run.passes
        )
    }
}
