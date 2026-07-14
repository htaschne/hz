//
//  HuffmanEngineTests.swift
//  hzTests
//
//  MIT License
//  See LICENSE file for details.

import Foundation
import Testing
@testable import hz

@Suite(.serialized)
struct HuffmanEngineTests {
    private let engine = SwiftHuffmanEngine()

    @Test func normalTextRoundTrip() throws {
        let input = Data("the quick brown fox jumps over the lazy dog".utf8)
        try expectRoundTrip(input)
    }

    @Test func maxDepthZeroProducesExactlyOneLayer() throws {
        let input = Data("single pass baseline".utf8)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 0, stopWhenNotSmaller: false)
        )
        let archive = try HzArchive.parse(result.archive)

        #expect(result.acceptedLayerCount == 1)
        #expect(result.passes.count == 1)
        #expect(archive.recursiveLayerCount == 1)
        #expect(try engine.decompress(result.archive) == input)
    }

    @Test func adaptiveStopsWhenNextArchiveIsEqualSize() throws {
        var outputs = [
            Data(repeating: 1, count: 10),
            Data(repeating: 2, count: 10)
        ]

        let run = try RecursiveCompressionController.run(
            input: Data(repeating: 0, count: 20),
            options: .adaptive,
            maximumAdditionalDepth: 10
        ) { _ in
            outputs.removeFirst()
        }

        #expect(run.acceptedLayerCount == 1)
        #expect(run.stoppingReason == .notSmaller)
        #expect(run.archive == Data(repeating: 1, count: 10))
        #expect(run.passes.map(\.accepted) == [true, false])
    }

    @Test func adaptiveStopsWhenNextArchiveIsLarger() throws {
        var outputs = [
            Data(repeating: 1, count: 10),
            Data(repeating: 2, count: 9),
            Data(repeating: 3, count: 12)
        ]

        let run = try RecursiveCompressionController.run(
            input: Data(repeating: 0, count: 20),
            options: .adaptive,
            maximumAdditionalDepth: 10
        ) { _ in
            outputs.removeFirst()
        }

        #expect(run.acceptedLayerCount == 2)
        #expect(run.stoppingReason == .notSmaller)
        #expect(run.archive == Data(repeating: 2, count: 9))
        #expect(run.passes.map(\.accepted) == [true, true, false])
    }

    @Test func nonImprovingCandidateIsDiscarded() throws {
        var outputs = [
            Data([1, 1]),
            Data([2, 2, 2])
        ]

        let run = try RecursiveCompressionController.run(
            input: Data([0, 0, 0, 0]),
            options: .adaptive,
            maximumAdditionalDepth: 10
        ) { _ in
            outputs.removeFirst()
        }

        #expect(run.archive == Data([1, 1]))
        #expect(run.passes.last?.accepted == false)
    }

    @Test func outermostArchiveRecordsAcceptedLayerCount() throws {
        let input = Data(repeating: 0x61, count: 4_096)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 2, stopWhenNotSmaller: false)
        )
        let archive = try HzArchive.parse(result.archive)

        #expect(result.acceptedLayerCount == 3)
        #expect(archive.recursiveLayerCount == 3)
    }

    @Test func innerLayersDoNotAdvertiseRecursiveDepth() throws {
        let input = Data(repeating: 0x62, count: 4_096)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 1, stopWhenNotSmaller: false)
        )
        let innerArchive = try engine.decompress(result.archive, options: .singleLayer)
        let outerArchive = try HzArchive.parse(result.archive)
        let parsedInnerArchive = try HzArchive.parse(innerArchive)

        #expect(outerArchive.recursiveLayerCount == 2)
        #expect(parsedInnerArchive.recursiveLayerCount == 0)
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
        archive[archive.startIndex + 5] = 1

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

    @Test func fullRecursiveDecompressionRestoresOriginalBytes() throws {
        let input = Data(("recursive " + String(repeating: "compression ", count: 500)).utf8)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 2, stopWhenNotSmaller: false)
        )

        #expect(try engine.decompress(result.archive, options: .full) == input)
    }

    @Test func partialDecompressionRemovesRequestedLayers() throws {
        let input = Data(repeating: 0x63, count: 8_192)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 2, stopWhenNotSmaller: false)
        )

        let afterOneLayer = try engine.decompress(result.archive, options: .singleLayer)
        let afterTwoLayers = try engine.decompress(
            result.archive,
            options: DecompressionOptions(maxAdditionalDepth: 1)
        )
        let afterOneLayerArchive = try HzArchive.parse(afterOneLayer)
        let afterTwoLayersArchive = try HzArchive.parse(afterTwoLayers)

        #expect(afterOneLayerArchive.recursiveLayerCount == 0)
        #expect(afterTwoLayersArchive.recursiveLayerCount == 0)
        #expect(afterOneLayer != afterTwoLayers)
        #expect(try engine.decompress(result.archive, options: .full) == input)
    }

    @Test func partialDecompressionReturnsValidRemainingArchive() throws {
        let input = Data(repeating: 0x64, count: 2_048)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 1, stopWhenNotSmaller: false)
        )
        let remainingArchive = try engine.decompress(result.archive, options: .singleLayer)

        #expect(remainingArchive.starts(with: HzArchive.magic))
        #expect(try engine.decompress(remainingArchive, options: .full) == input)
    }

    @Test func corruptedRecordedLayerCountThrows() throws {
        var archive = try engine.compress(Data("not recursive".utf8))
        archive[archive.startIndex + 6] = 3
        archive[archive.startIndex + 7] = 0

        expectThrows {
            _ = try engine.decompress(archive, options: .full)
        }
    }

    @Test func forcedModeReachesConfiguredMaximumWhenSizeGrows() throws {
        let input = deterministicHighEntropyData(count: 512)
        let result = try engine.compress(
            input,
            options: CompressionOptions(maxAdditionalDepth: 2, stopWhenNotSmaller: false)
        )

        #expect(result.acceptedLayerCount == 3)
        #expect(result.passes.count == 3)
        #expect(result.stoppingReason == .reachedMaxDepth)
        #expect(result.passes.map(\.accepted) == [true, true, true])
        #expect(try engine.decompress(result.archive, options: .full) == input)
    }

    @Test func compressionAndDecompressionAreDeterministic() throws {
        let input = Data("deterministic deterministic deterministic".utf8)
        let first = try engine.compress(input, options: .adaptive)
        let second = try engine.compress(input, options: .adaptive)
        let firstOutput = try engine.decompress(first.archive)
        let secondOutput = try engine.decompress(second.archive)

        #expect(first == second)
        #expect(firstOutput == secondOutput)
    }

    private func expectRoundTrip(_ input: Data) throws {
        let archive = try engine.compress(input, options: .adaptive).archive
        let output = try engine.decompress(archive, options: .full)
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

    private func deterministicHighEntropyData(count: Int) -> Data {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)

        for _ in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            bytes.append(UInt8(truncatingIfNeeded: state >> 56))
        }

        return Data(bytes)
    }

    private func expectThrows(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected operation to throw")
        } catch {
            return
        }
    }
}

private enum TestInputError: Error {
    case noNonByteAlignedCandidate
}
