//
//  HuffmanEngineTests.swift
//  hzTests
//
//  MIT License
//  See LICENSE file for details.

import Foundation
import Testing
@testable import hz

struct HuffmanEngineTests {
    private let engine = SwiftHuffmanEngine()

    @Test func normalTextRoundTrip() throws {
        let input = Data("the quick brown fox jumps over the lazy dog".utf8)
        try expectRoundTrip(input)
    }

    @Test func emptyInputRoundTrip() throws {
        try expectRoundTrip(Data())
    }

    @Test func singleRepeatedByteRoundTrip() throws {
        try expectRoundTrip(Data(repeating: 0x41, count: 1_024))
    }

    @Test func binaryDataContainingZeroBytesRoundTrip() throws {
        let input = Data([0, 1, 2, 0, 255, 0, 128, 64, 0, 32, 16])
        try expectRoundTrip(input)
    }

    @Test func nonByteAlignedPayloadRoundTrip() throws {
        let input = try makeNonByteAlignedInput()
        let archive = try HzArchive.parse(engine.compress(input))

        #expect(archive.encodedBitCount % 8 != 0)
        #expect(try engine.decompress(archive.serialize()) == input)
    }

    @Test func corruptedHeaderThrows() throws {
        var archive = try engine.compress(Data("hello".utf8))
        archive[archive.startIndex + 4] = 2

        expectThrows {
            _ = try engine.decompress(archive)
        }
    }

    @Test func invalidMagicNumberThrows() {
        let archive = Data("NOPE".utf8) + Data(repeating: 0, count: 32)

        expectThrows {
            _ = try engine.decompress(archive)
        }
    }

    @Test func truncatedArchiveThrows() throws {
        var archive = try engine.compress(Data("truncated archive".utf8))
        archive.removeLast()

        expectThrows {
            _ = try engine.decompress(archive)
        }
    }

    @Test func paddingBitsNeverCreateAdditionalOutput() throws {
        let input = try makeNonByteAlignedInput()
        let compressed = try engine.compress(input)
        let archive = try HzArchive.parse(compressed)
        let paddingBitCount = UInt8(8 - (archive.encodedBitCount % 8))

        #expect(paddingBitCount > 0 && paddingBitCount < 8)

        var mutated = compressed
        let lastIndex = mutated.index(before: mutated.endIndex)
        mutated[lastIndex] |= UInt8((1 << paddingBitCount) - 1)

        #expect(try engine.decompress(mutated) == input)
    }

    private func expectRoundTrip(_ input: Data) throws {
        let archive = try engine.compress(input)
        let output = try engine.decompress(archive)
        #expect(output == input)
    }

    private func makeNonByteAlignedInput() throws -> Data {
        let candidates: [Data] = [
            Data("abc".utf8),
            Data("hello world".utf8),
            Data([0, 1, 2, 3, 4]),
            Data("padding bits should not decode".utf8)
        ]

        for candidate in candidates {
            let archive = try HzArchive.parse(engine.compress(candidate))
            if archive.encodedBitCount % 8 != 0 {
                return candidate
            }
        }

        throw TestInputError.noNonByteAlignedCandidate
    }

    private func expectThrows(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected operation to throw")
        } catch {
            #expect(true)
        }
    }
}

private enum TestInputError: Error {
    case noNonByteAlignedCandidate
}

