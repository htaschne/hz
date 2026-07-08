//
//  CompressionEngine.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

protocol CompressionEngine {
    func compress(_ input: Data) throws -> Data
    func decompress(_ archive: Data) throws -> Data
}

