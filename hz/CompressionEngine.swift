//
//  CompressionEngine.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct CompressionOptions: Equatable {
    static let adaptive = CompressionOptions(
        maxAdditionalDepth: nil,
        stopWhenNotSmaller: true
    )

    static let singlePass = CompressionOptions(
        maxAdditionalDepth: 0,
        stopWhenNotSmaller: false
    )

    let maxAdditionalDepth: Int?
    let stopWhenNotSmaller: Bool

    init(maxAdditionalDepth: Int?, stopWhenNotSmaller: Bool) {
        self.maxAdditionalDepth = maxAdditionalDepth
        self.stopWhenNotSmaller = stopWhenNotSmaller
    }
}

struct DecompressionOptions: Equatable {
    static let full = DecompressionOptions(maxAdditionalDepth: nil)
    static let singleLayer = DecompressionOptions(maxAdditionalDepth: 0)

    let maxAdditionalDepth: Int?
}

struct CompressionResult: Equatable {
    let archive: Data
    let acceptedLayerCount: Int
    let stoppingReason: CompressionStoppingReason
    let passes: [CompressionPass]

    var bestPass: CompressionPass? {
        passes.min { lhs, rhs in
            if lhs.outputByteCount != rhs.outputByteCount {
                return lhs.outputByteCount < rhs.outputByteCount
            }

            return lhs.layer < rhs.layer
        }
    }
}

struct CompressionPass: Equatable {
    let layer: Int
    let inputByteCount: Int
    let outputByteCount: Int
    let ratio: Double
    let accepted: Bool
}

enum CompressionStoppingReason: String {
    case reachedMaxDepth
    case notSmaller
    case safetyLimitReached
}

enum CompressionEngineError: Error, Equatable {
    case negativeMaximumDepth
    case maximumDepthExceedsSafetyLimit(maximum: Int)
    case emptyCompressionPasses
    case invalidRecordedLayerCount(UInt16)
    case missingNestedArchive(expectedLayer: Int)
}

protocol CompressionEngine {
    func compress(_ input: Data, options: CompressionOptions) throws -> CompressionResult
    func decompress(_ archive: Data, options: DecompressionOptions) throws -> Data
}

extension CompressionEngine {
    func compress(_ input: Data) throws -> Data {
        try compress(input, options: .singlePass).archive
    }

    func decompress(_ archive: Data) throws -> Data {
        try decompress(archive, options: .full)
    }
}
