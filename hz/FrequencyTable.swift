//
//  FrequencyTable.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

struct FrequencyTable {
    static func make(from data: Data) -> [UInt8: UInt64] {
        var frequencies: [UInt8: UInt64] = [:]
        frequencies.reserveCapacity(256)

        for byte in data {
            frequencies[byte, default: 0] += 1
        }

        return frequencies
    }
}

