//
//  HuffmanTree.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

enum HuffmanTreeError: Error {
    case emptyTree
    case invalidBitstream
    case invalidSingleSymbolBitstream
}

struct HuffmanTree {
    private final class Node {
        let byte: UInt8?
        let frequency: UInt64
        let minimumByte: UInt8
        let left: Node?
        let right: Node?

        init(byte: UInt8, frequency: UInt64) {
            self.byte = byte
            self.frequency = frequency
            self.minimumByte = byte
            self.left = nil
            self.right = nil
        }

        init(left: Node, right: Node) {
            self.byte = nil
            self.frequency = left.frequency + right.frequency
            self.minimumByte = min(left.minimumByte, right.minimumByte)
            self.left = left
            self.right = right
        }

        var isLeaf: Bool {
            byte != nil
        }
    }

    private let root: Node

    static func build(frequencies: [UInt8: UInt64]) -> HuffmanTree? {
        var nodes = frequencies
            .filter { $0.value > 0 }
            .map { Node(byte: $0.key, frequency: $0.value) }

        guard !nodes.isEmpty else {
            return nil
        }

        while nodes.count > 1 {
            nodes.sort(by: Self.isHigherPriority)
            let left = nodes.removeFirst()
            let right = nodes.removeFirst()
            nodes.append(Node(left: left, right: right))
        }

        return HuffmanTree(root: nodes[0])
    }

    func makeCodeTable() -> [UInt8: [Bool]] {
        var table: [UInt8: [Bool]] = [:]
        buildCodeTable(from: root, prefix: [], into: &table)
        return table
    }

    func decode(
        payload: Data,
        encodedBitCount: UInt64,
        originalByteCount: UInt64
    ) throws -> Data {
        guard originalByteCount > 0 else {
            return Data()
        }

        if root.isLeaf {
            return try decodeSingleSymbolPayload(
                payload: payload,
                encodedBitCount: encodedBitCount,
                originalByteCount: originalByteCount
            )
        }

        var reader = BitReader(data: payload, bitCount: encodedBitCount)
        var decoded = Data()
        decoded.reserveCapacity(Int(min(originalByteCount, UInt64(Int.max))))

        var node = root
        for _ in 0..<encodedBitCount {
            let bit = try reader.readBit()
            guard let nextNode = bit ? node.right : node.left else {
                throw HuffmanTreeError.invalidBitstream
            }

            node = nextNode

            if let byte = node.byte {
                decoded.append(byte)
                guard UInt64(decoded.count) <= originalByteCount else {
                    throw HuffmanTreeError.invalidBitstream
                }

                if UInt64(decoded.count) == originalByteCount {
                    return decoded
                }

                node = root
            }
        }

        guard UInt64(decoded.count) == originalByteCount else {
            throw HuffmanTreeError.invalidBitstream
        }

        return decoded
    }

    private init(root: Node) {
        self.root = root
    }

    private static func isHigherPriority(_ lhs: Node, _ rhs: Node) -> Bool {
        if lhs.frequency != rhs.frequency {
            return lhs.frequency < rhs.frequency
        }

        return lhs.minimumByte < rhs.minimumByte
    }

    private func buildCodeTable(
        from node: Node,
        prefix: [Bool],
        into table: inout [UInt8: [Bool]]
    ) {
        if let byte = node.byte {
            table[byte] = prefix.isEmpty ? [false] : prefix
            return
        }

        if let left = node.left {
            buildCodeTable(from: left, prefix: prefix + [false], into: &table)
        }

        if let right = node.right {
            buildCodeTable(from: right, prefix: prefix + [true], into: &table)
        }
    }

    private func decodeSingleSymbolPayload(
        payload: Data,
        encodedBitCount: UInt64,
        originalByteCount: UInt64
    ) throws -> Data {
        guard encodedBitCount == originalByteCount, let byte = root.byte else {
            throw HuffmanTreeError.invalidSingleSymbolBitstream
        }

        var reader = BitReader(data: payload, bitCount: encodedBitCount)
        for _ in 0..<encodedBitCount {
            guard try reader.readBit() == false else {
                throw HuffmanTreeError.invalidSingleSymbolBitstream
            }
        }

        return Data(repeating: byte, count: Int(originalByteCount))
    }
}

