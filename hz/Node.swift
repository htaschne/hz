//
//  Node.swift
//  hz
//
//  Created by Agatha Schneider on 17/04/25.
//
//  MIT License
//  See LICENSE file for details.

class Node: Comparable {
    let byte: UInt8
    let count: Int
    var lo: Node?
    var hi: Node?
    var encoding: String?

    init(
        byte: UInt8,
        count: Int,
        lo: Node? = nil,
        hi: Node? = nil,
        encoding: String? = nil
    ) {
        self.byte = byte
        self.count = count
        self.lo = lo
        self.hi = hi
        self.encoding = encoding
    }

    static func < (lhs: Node, rhs: Node) -> Bool {
        return rhs.count < lhs.count
    }

    // implement to string method
    func description(_ prefix: String = "") -> String {
        return "\(byte): \(count)"
    }

    static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.count == rhs.count && lhs.byte == rhs.byte
    }

}
