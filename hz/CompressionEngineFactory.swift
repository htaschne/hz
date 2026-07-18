//
//  CompressionEngineFactory.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

enum CompressionEngineKind: String, CaseIterable {
    case swift
    case rust
}

struct CompressionEngineFactory {
    static let defaultKind: CompressionEngineKind = .swift

    static func make(_ kind: CompressionEngineKind = defaultKind) -> any CompressionEngine {
        switch kind {
        case .swift:
            return SwiftHuffmanEngine()
        case .rust:
            return RustHuffmanEngine()
        }
    }
}
