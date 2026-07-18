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
        #expect(!info.supportsCompression)
    }

    @Test func rustCompressionMapsNotImplemented() {
        expectNotImplemented("compression") {
            _ = try RustHuffmanEngine().compress(Data("hello".utf8), options: .singlePass)
        }
    }

    @Test func rustDecompressionMapsNotImplemented() {
        expectNotImplemented("decompression") {
            _ = try RustHuffmanEngine().decompress(Data("archive".utf8), options: .full)
        }
    }

    @Test func emptyDataCrossesNativeBoundarySafely() {
        expectNotImplemented("compression") {
            _ = try RustHuffmanEngine().compress(Data(), options: .singlePass)
        }
    }

    @Test func swiftEngineRemainsDefault() {
        #expect(CompressionEngineFactory.defaultKind == .swift)
        #expect(CompressionEngineFactory.make() is SwiftHuffmanEngine)
        #expect(FileCompressionService().engine is SwiftHuffmanEngine)
    }

    private func expectNotImplemented(
        _ expectedText: String,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected Rust native engine to report not implemented")
        } catch NativeEngineError.notImplemented(let message) {
            #expect(message.localizedCaseInsensitiveContains(expectedText))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
