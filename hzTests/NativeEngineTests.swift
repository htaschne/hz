//
//  NativeEngineTests.swift
//  hzTests
//
//  MIT License
//  See LICENSE file for details.

import Foundation
import HzNative
import Testing
@testable import hz

@Suite(.serialized)
struct NativeEngineTests {
    @Test func nativeModuleImportsAndAbiVersionIsReadable() {
        #expect(hz_native_abi_version() > 0)
    }

    @Test func nativeVersionStringIsReadable() {
        let version = String(cString: hz_native_version_string())

        #expect(!version.isEmpty)
        #expect(version.contains("hz-native"))
    }

    @Test func nativeBridgeAvailabilityIsTrue() {
        let info = RustHuffmanEngine.info

        #expect(info.isBridgeAvailable)
        #expect(info.abiVersion > 0)
        #expect(!info.version.isEmpty)
        #expect(info.supportsCompression)
    }

    @Test func rustEngineRoundTripsNormalText() throws {
        try expectRustRoundTrip(Data("the quick brown fox jumps over the lazy dog".utf8))
    }

    @Test func rustEngineRoundTripsEmptyInput() throws {
        try expectRustRoundTrip(Data())
    }

    @Test func rustEngineRoundTripsSingleRepeatedByte() throws {
        try expectRustRoundTrip(Data(repeating: 0x41, count: 1_024))
    }

    @Test func rustEngineRoundTripsBinaryZeroBytes() throws {
        try expectRustRoundTrip(Data([0, 1, 0, 2, 0, 3, 255, 0]))
    }

    @Test func swiftArchiveDecompressesWithRustEngine() throws {
        let input = Data("Swift archive decoded by Rust".utf8)
        let archive = try SwiftHuffmanEngine().compress(input, options: .singlePass).archive

        #expect(try RustHuffmanEngine().decompress(archive, options: .full) == input)
    }

    @Test func rustArchiveDecompressesWithSwiftEngine() throws {
        let input = Data("Rust archive decoded by Swift".utf8)
        let archive = try RustHuffmanEngine().compress(input, options: .singlePass).archive

        #expect(try SwiftHuffmanEngine().decompress(archive, options: .full) == input)
    }

    @Test func rustPaddingBitsNeverCreateAdditionalOutput() throws {
        let input = try makeNonByteAlignedInput()
        let compressed = try RustHuffmanEngine().compress(input, options: .singlePass).archive
        let archive = try HzArchive.parse(compressed)
        let paddingBitCount = UInt8(8 - (archive.encodedBitCount % 8))

        #expect(paddingBitCount > 0 && paddingBitCount < 8)

        var mutated = compressed
        let lastIndex = mutated.index(before: mutated.endIndex)
        mutated[lastIndex] |= UInt8((1 << paddingBitCount) - 1)

        #expect(try RustHuffmanEngine().decompress(mutated, options: .full) == input)
    }

    @Test func rustInvalidMagicThrows() {
        let archive = Data("NOPE".utf8) + Data(repeating: 0, count: 32)

        expectThrows {
            _ = try RustHuffmanEngine().decompress(archive, options: .full)
        }
    }

    @Test func rustTruncatedArchiveThrows() throws {
        var archive = try RustHuffmanEngine()
            .compress(Data("truncated archive".utf8), options: .singlePass)
            .archive
        archive.removeLast()

        expectThrows {
            _ = try RustHuffmanEngine().decompress(archive, options: .full)
        }
    }

    @Test func swiftEngineRemainsDefault() {
        #expect(CompressionEngineFactory.defaultKind == .swift)
        #expect(CompressionEngineFactory.make() is SwiftHuffmanEngine)
        #expect(FileCompressionService().engine is SwiftHuffmanEngine)
    }

    private func expectRustRoundTrip(_ input: Data) throws {
        let engine = RustHuffmanEngine()
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
            let archive = try HzArchive.parse(
                RustHuffmanEngine().compress(candidate, options: .singlePass).archive
            )
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
            return
        }
    }
}

private enum TestInputError: Error {
    case noNonByteAlignedCandidate
}
