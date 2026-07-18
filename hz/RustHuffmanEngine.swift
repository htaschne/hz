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
    static var info: RustEngineInfo {
        RustEngineInfo(
            abiVersion: hz_native_abi_version(),
            version: String(cString: hz_native_version_string()),
            isBridgeAvailable: hz_native_is_available(),
            supportsCompression: false
        )
    }

    func compress(_ input: Data, options: CompressionOptions) throws -> CompressionResult {
        let archive = try callNative(input, operation: hz_native_compress)
        return CompressionResult(
            archive: archive,
            acceptedLayerCount: 1,
            stoppingReason: .reachedMaxDepth,
            passes: [
                CompressionPass(
                    layer: 1,
                    inputByteCount: input.count,
                    outputByteCount: archive.count,
                    ratio: input.isEmpty ? 0 : Double(archive.count) / Double(input.count),
                    accepted: true
                )
            ]
        )
    }

    func decompress(_ archive: Data, options: DecompressionOptions) throws -> Data {
        try callNative(archive, operation: hz_native_decompress)
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
