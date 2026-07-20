//
//  FileCompressionState.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

enum FileOperation: String, Equatable {
    case compress
    case decompress

    var title: String {
        switch self {
        case .compress:
            return "Compress"
        case .decompress:
            return "Decompress"
        }
    }

    var runningTitle: String {
        switch self {
        case .compress:
            return "Compressing"
        case .decompress:
            return "Decompressing"
        }
    }

    var completedTitle: String {
        switch self {
        case .compress:
            return "Compressed"
        case .decompress:
            return "Decompressed"
        }
    }
}

struct SelectedFile: Equatable {
    let url: URL
    let operation: FileOperation
    let byteCount: Int64?

    var suggestedOutputName: String {
        switch operation {
        case .compress:
            return "\(url.lastPathComponent).hz"
        case .decompress:
            guard url.pathExtension.lowercased() == "hz" else {
                return "\(url.lastPathComponent).decoded"
            }

            let baseName = String(url.lastPathComponent.dropLast(3))
            return baseName.isEmpty ? "decompressed-output" : baseName
        }
    }
}

struct OperationProgress: Equatable {
    let operation: FileOperation
    let sourceURL: URL
    let destinationURL: URL
    let message: String
    let fractionCompleted: Double?
}

struct OperationResult: Equatable {
    let operation: FileOperation
    let sourceURL: URL
    let destinationURL: URL
    let inputByteCount: Int64?
    let outputByteCount: Int64?
    let elapsedTime: TimeInterval

    var byteDelta: Int64? {
        guard let inputByteCount, let outputByteCount else {
            return nil
        }

        return inputByteCount - outputByteCount
    }
}

struct OperationFailure: Equatable {
    let title: String
    let message: String
    let technicalDetails: String
    let sourceURL: URL?
}

enum FileCompressionState: Equatable {
    case empty
    case selected(SelectedFile)
    case processing(OperationProgress)
    case success(OperationResult)
    case failure(OperationFailure)

    var phaseID: String {
        switch self {
        case .empty:
            return "empty"
        case .selected:
            return "selected"
        case .processing:
            return "processing"
        case .success:
            return "success"
        case .failure:
            return "failure"
        }
    }
}
