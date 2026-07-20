//
//  RustHuffmanEngine.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation
import HzNative

struct RustEngineInfo: Equatable {
    let abiVersion: UInt32
    let version: String
    let isBridgeAvailable: Bool
    let supportsCompression: Bool
}

struct RustHuffmanEngine: CompressionEngine {
    static let maximumAdditionalDepth = 32

    static var info: RustEngineInfo {
        RustEngineInfo(
            abiVersion: hz_native_abi_version(),
            version: String(cString: hz_native_version_string()),
            isBridgeAvailable: hz_native_is_available(),
            supportsCompression: true
        )
    }

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

        var currentBytes = archive

        for layerIndex in 1...layersToRemove {
            currentBytes = try callNative(currentBytes, operation: hz_native_decompress)

            if layerIndex < layersToRemove {
                guard currentBytes.starts(with: HzArchive.magic) else {
                    throw CompressionEngineError.missingNestedArchive(expectedLayer: layerIndex + 1)
                }

                _ = try HzArchive.parse(currentBytes)
            }
        }

        return currentBytes
    }

    func compressFile(at sourceURL: URL, to destinationURL: URL) throws {
        try callNativeFile(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            operation: hz_native_compress_file
        )
    }

    func decompressFile(at sourceURL: URL, to destinationURL: URL) throws {
        try callNativeFile(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            operation: hz_native_decompress_file
        )
    }

    private func makeLayerArchive(from input: Data, recursiveLayerCount: UInt16) throws -> Data {
        try HzArchive.parse(callNative(input, operation: hz_native_compress))
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

        let archive = try parsedArchive
            .withRecursiveLayerCount(UInt16(run.acceptedLayerCount))
            .serialize()

        return CompressionResult(
            archive: archive,
            acceptedLayerCount: run.acceptedLayerCount,
            stoppingReason: run.stoppingReason,
            passes: run.passes
        )
    }

    private func callNative(
        _ input: Data,
        operation: (UnsafePointer<UInt8>?, Int) -> HzNativeResult
    ) throws -> Data {
        guard hz_native_is_available() else {
            throw NativeEngineError.unavailable
        }

        let result = input.withUnsafeBytes { rawBuffer -> HzNativeResult in
            guard let baseAddress = rawBuffer.baseAddress else {
                return operation(nil, 0)
            }

            return operation(baseAddress.assumingMemoryBound(to: UInt8.self), rawBuffer.count)
        }

        defer {
            hz_native_result_free(result)
        }

        return try data(from: result)
    }

    private func callNativeFile(
        sourceURL: URL,
        destinationURL: URL,
        operation: (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> HzNativeResult
    ) throws {
        guard hz_native_is_available() else {
            throw NativeEngineError.unavailable
        }

        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                operation(sourcePath, destinationPath)
            }
        }

        defer {
            hz_native_result_free(result)
        }

        _ = try data(from: result)
    }

    private func data(from result: HzNativeResult) throws -> Data {
        if result.status == HZ_NATIVE_OK {
            guard result.buffer.length > 0 else {
                return Data()
            }

            guard let bytes = result.buffer.data else {
                throw NativeEngineError.internalError("native result had nonzero length with null buffer")
            }

            return Data(bytes: bytes, count: result.buffer.length)
        }

        let message = errorMessage(from: result)

        if result.status == HZ_NATIVE_NOT_IMPLEMENTED {
            throw NativeEngineError.notImplemented(message)
        }
        if result.status == HZ_NATIVE_INVALID_ARGUMENT {
            throw NativeEngineError.invalidArgument(message)
        }
        if result.status == HZ_NATIVE_ALLOCATION_FAILED {
            throw NativeEngineError.allocationFailed(message)
        }
        if result.status == HZ_NATIVE_INTERNAL_ERROR {
            throw NativeEngineError.internalError(message)
        }

        throw NativeEngineError.unknownStatus(Int32(result.status.rawValue), message)
    }

    private func errorMessage(from result: HzNativeResult) -> String {
        guard let pointer = result.error_message else {
            return ""
        }

        return String(cString: pointer)
    }
}
