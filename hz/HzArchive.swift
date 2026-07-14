//
//  HzArchive.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

/// Version 2 `.hz` archive format.
///
/// Multi-byte integers are little-endian.
///
/// Header:
/// - 4 bytes: magic bytes, ASCII "HZF1"
/// - 1 byte: format version, currently 2
/// - 1 byte: flags, currently 0
/// - 2 bytes: recursive layer count
///   - 0 means this archive does not advertise total recursion depth
///   - the outermost archive writes the total accepted Huffman layer count
///   - inner recursive layers write 0 so they remain independently decodable
/// - 8 bytes: original uncompressed byte count
/// - 8 bytes: encoded payload bit count
/// - 2 bytes: frequency table entry count
/// - N entries:
///   - 1 byte: symbol
///   - 8 bytes: symbol frequency in the original input
/// - remaining bytes: Huffman encoded payload, padded with zero bits to the next byte
///
/// Decoders must use `originalByteCount` and `encodedBitCount` when decoding.
/// Padding bits are not part of the bitstream and must never produce output.
struct HzArchive {
    enum Error: Swift.Error, Equatable {
        case unsupportedLegacyArchive
        case truncatedHeader
        case invalidVersion(UInt8)
        case unsupportedFlags(UInt8)
        case invalidRecursiveLayerCount
        case invalidFrequencyTable
        case duplicateFrequency(UInt8)
        case frequencyTotalMismatch(expected: UInt64, actual: UInt64)
        case invalidEncodedBitCount
        case payloadTooLarge
        case payloadLengthMismatch(expected: Int, actual: Int)
    }

    static let magic = Array("HZF1".utf8)
    static let currentVersion: UInt8 = 2
    static let supportedFlags: UInt8 = 0

    let flags: UInt8
    let recursiveLayerCount: UInt16
    let originalByteCount: UInt64
    let encodedBitCount: UInt64
    let frequencies: [UInt8: UInt64]
    let payload: Data

    func serialize() throws -> Data {
        guard frequencies.count <= Int(UInt16.max) else {
            throw Error.invalidFrequencyTable
        }

        var data = Data()
        data.append(contentsOf: Self.magic)
        data.append(Self.currentVersion)
        data.append(flags)
        data.appendLittleEndian(recursiveLayerCount)
        data.appendLittleEndian(originalByteCount)
        data.appendLittleEndian(encodedBitCount)
        data.appendLittleEndian(UInt16(frequencies.count))

        for (byte, frequency) in frequencies.sorted(by: { $0.key < $1.key }) {
            data.append(byte)
            data.appendLittleEndian(frequency)
        }

        data.append(payload)
        return data
    }

    static func parse(_ data: Data) throws -> HzArchive {
        var reader = ArchiveReader(data: data)

        guard let magic = reader.readBytes(count: Self.magic.count) else {
            throw Error.truncatedHeader
        }

        guard Array(magic) == Self.magic else {
            throw Error.unsupportedLegacyArchive
        }

        guard let version = reader.readUInt8() else {
            throw Error.truncatedHeader
        }

        guard version == Self.currentVersion else {
            if version == 1 {
                throw Error.unsupportedLegacyArchive
            }

            throw Error.invalidVersion(version)
        }

        guard
            let flags = reader.readUInt8(),
            let recursiveLayerCount = reader.readUInt16(),
            let originalByteCount = reader.readUInt64(),
            let encodedBitCount = reader.readUInt64(),
            let entryCount = reader.readUInt16()
        else {
            throw Error.truncatedHeader
        }

        guard flags == Self.supportedFlags else {
            throw Error.unsupportedFlags(flags)
        }

        guard recursiveLayerCount != 0 || originalByteCount > 0 || encodedBitCount == 0 else {
            throw Error.invalidRecursiveLayerCount
        }

        var frequencies: [UInt8: UInt64] = [:]
        frequencies.reserveCapacity(Int(entryCount))

        for _ in 0..<entryCount {
            guard let byte = reader.readUInt8(), let frequency = reader.readUInt64() else {
                throw Error.truncatedHeader
            }

            guard frequency > 0 else {
                throw Error.invalidFrequencyTable
            }

            guard frequencies[byte] == nil else {
                throw Error.duplicateFrequency(byte)
            }

            frequencies[byte] = frequency
        }

        let frequencyTotal = frequencies.values.reduce(UInt64(0), +)
        guard frequencyTotal == originalByteCount else {
            throw Error.frequencyTotalMismatch(
                expected: originalByteCount,
                actual: frequencyTotal
            )
        }

        if originalByteCount == 0 {
            guard frequencies.isEmpty, encodedBitCount == 0 else {
                throw Error.invalidFrequencyTable
            }
        } else {
            guard !frequencies.isEmpty, encodedBitCount > 0 else {
                throw Error.invalidEncodedBitCount
            }
        }

        let expectedPayloadLengthUInt64 =
            encodedBitCount / 8 + (encodedBitCount % 8 == 0 ? 0 : 1)
        guard expectedPayloadLengthUInt64 <= UInt64(Int.max) else {
            throw Error.payloadTooLarge
        }

        let expectedPayloadLength = Int(expectedPayloadLengthUInt64)
        let actualPayloadLength = data.endIndex - reader.offset
        guard actualPayloadLength == expectedPayloadLength else {
            throw Error.payloadLengthMismatch(
                expected: expectedPayloadLength,
                actual: actualPayloadLength
            )
        }

        let payload = data.subdata(in: reader.offset..<data.endIndex)
        return HzArchive(
            flags: flags,
            recursiveLayerCount: recursiveLayerCount,
            originalByteCount: originalByteCount,
            encodedBitCount: encodedBitCount,
            frequencies: frequencies,
            payload: payload
        )
    }

    func withRecursiveLayerCount(_ layerCount: UInt16) -> HzArchive {
        HzArchive(
            flags: flags,
            recursiveLayerCount: layerCount,
            originalByteCount: originalByteCount,
            encodedBitCount: encodedBitCount,
            frequencies: frequencies,
            payload: payload
        )
    }
}

private struct ArchiveReader {
    let data: Data
    private(set) var offset: Data.Index

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func readUInt8() -> UInt8? {
        guard offset < data.endIndex else {
            return nil
        }

        defer {
            offset = data.index(after: offset)
        }

        return data[offset]
    }

    mutating func readUInt16() -> UInt16? {
        guard let bytes = readBytes(count: MemoryLayout<UInt16>.size) else {
            return nil
        }

        return bytes.enumerated().reduce(UInt16(0)) { value, element in
            value | (UInt16(element.element) << UInt16(element.offset * 8))
        }
    }

    mutating func readUInt64() -> UInt64? {
        guard let bytes = readBytes(count: MemoryLayout<UInt64>.size) else {
            return nil
        }

        return bytes.enumerated().reduce(UInt64(0)) { value, element in
            value | (UInt64(element.element) << UInt64(element.offset * 8))
        }
    }

    mutating func readBytes(count: Int) -> Data? {
        guard count >= 0, data.distance(from: offset, to: data.endIndex) >= count else {
            return nil
        }

        let start = offset
        let end = data.index(offset, offsetBy: count)
        offset = end
        return data.subdata(in: start..<end)
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { bytes in
            append(contentsOf: bytes)
        }
    }
}
