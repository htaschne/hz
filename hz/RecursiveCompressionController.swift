//
//  RecursiveCompressionController.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct RecursiveCompressionRun: Equatable {
    let archive: Data
    let acceptedLayerCount: Int
    let stoppingReason: CompressionStoppingReason
    let passes: [CompressionPass]
}

struct RecursiveCompressionController {
    static func run(
        input: Data,
        options: CompressionOptions,
        maximumAdditionalDepth: Int,
        makeLayerArchive: (Data) throws -> Data
    ) throws -> RecursiveCompressionRun {
        let maxAdditionalDepth = try validatedMaxAdditionalDepth(
            options.maxAdditionalDepth,
            maximumAdditionalDepth: maximumAdditionalDepth
        )
        let maxLayerCount = maxAdditionalDepth.map { $0 + 1 }

        var passes: [CompressionPass] = []
        var currentInput = input
        var currentArchive = try makeLayerArchive(currentInput)
        var acceptedLayerCount = 1

        passes.append(
            CompressionPass(
                layer: 1,
                inputByteCount: currentInput.count,
                outputByteCount: currentArchive.count,
                ratio: ratio(outputByteCount: currentArchive.count, inputByteCount: currentInput.count),
                accepted: true
            )
        )

        while true {
            if let maxLayerCount, acceptedLayerCount >= maxLayerCount {
                return RecursiveCompressionRun(
                    archive: currentArchive,
                    acceptedLayerCount: acceptedLayerCount,
                    stoppingReason: .reachedMaxDepth,
                    passes: passes
                )
            }

            if maxLayerCount == nil && acceptedLayerCount >= maximumAdditionalDepth + 1 {
                return RecursiveCompressionRun(
                    archive: currentArchive,
                    acceptedLayerCount: acceptedLayerCount,
                    stoppingReason: .safetyLimitReached,
                    passes: passes
                )
            }

            currentInput = currentArchive
            let nextArchive = try makeLayerArchive(currentInput)
            let nextLayer = acceptedLayerCount + 1
            let isSmaller = nextArchive.count < currentArchive.count
            let accepted = !options.stopWhenNotSmaller || isSmaller

            passes.append(
                CompressionPass(
                    layer: nextLayer,
                    inputByteCount: currentInput.count,
                    outputByteCount: nextArchive.count,
                    ratio: ratio(outputByteCount: nextArchive.count, inputByteCount: currentInput.count),
                    accepted: accepted
                )
            )

            guard accepted else {
                return RecursiveCompressionRun(
                    archive: currentArchive,
                    acceptedLayerCount: acceptedLayerCount,
                    stoppingReason: .notSmaller,
                    passes: passes
                )
            }

            currentArchive = nextArchive
            acceptedLayerCount = nextLayer
        }
    }

    private static func validatedMaxAdditionalDepth(
        _ maxAdditionalDepth: Int?,
        maximumAdditionalDepth: Int
    ) throws -> Int? {
        guard let maxAdditionalDepth else {
            return nil
        }

        guard maxAdditionalDepth >= 0 else {
            throw CompressionEngineError.negativeMaximumDepth
        }

        guard maxAdditionalDepth <= maximumAdditionalDepth else {
            throw CompressionEngineError.maximumDepthExceedsSafetyLimit(
                maximum: maximumAdditionalDepth
            )
        }

        return maxAdditionalDepth
    }

    private static func ratio(outputByteCount: Int, inputByteCount: Int) -> Double {
        guard inputByteCount > 0 else {
            return outputByteCount == 0 ? 1.0 : Double.infinity
        }

        return Double(outputByteCount) / Double(inputByteCount)
    }
}

