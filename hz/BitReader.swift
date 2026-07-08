//
//  BitReader.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct BitReader {
    enum Error: Swift.Error {
        case readPastEnd
    }

    private let data: Data
    private let bitCount: UInt64
    private var bitsRead: UInt64 = 0

    init(data: Data, bitCount: UInt64) {
        self.data = data
        self.bitCount = bitCount
    }

    mutating func readBit() throws -> Bool {
        guard bitsRead < bitCount else {
            throw Error.readPastEnd
        }

        let byteIndex = data.startIndex + Int(bitsRead / 8)
        guard byteIndex < data.endIndex else {
            throw Error.readPastEnd
        }

        let shift = 7 - UInt8(bitsRead % 8)
        let bit = ((data[byteIndex] >> shift) & 1) == 1
        bitsRead += 1
        return bit
    }
}

