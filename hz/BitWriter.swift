//
//  BitWriter.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct BitWriter {
    private(set) var data = Data()
    private(set) var bitCount: UInt64 = 0

    private var currentByte: UInt8 = 0
    private var bitIndex: UInt8 = 0

    mutating func writeBit(_ bit: Bool) {
        if bit {
            currentByte |= 1 << (7 - bitIndex)
        }

        bitIndex += 1
        bitCount += 1

        if bitIndex == 8 {
            data.append(currentByte)
            currentByte = 0
            bitIndex = 0
        }
    }

    mutating func writeBits(_ bits: [Bool]) {
        for bit in bits {
            writeBit(bit)
        }
    }

    mutating func finish() -> Data {
        if bitIndex > 0 {
            data.append(currentByte)
            currentByte = 0
            bitIndex = 0
        }

        return data
    }
}

