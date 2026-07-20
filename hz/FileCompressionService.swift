//
//  FileCompressionService.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

enum FileCompressionServiceError: Error {
    case temporaryDirectoryCreationFailed(url: URL, diagnostics: FileDiagnostics, underlying: Error)
    case temporaryOutputCleanupFailed(url: URL, diagnostics: FileDiagnostics, underlying: Error)
    case outputReplacementFailed(
        temporaryURL: URL,
        destinationURL: URL,
        destinationDiagnostics: FileDiagnostics,
        temporaryDiagnostics: FileDiagnostics,
        underlying: Error
    )
}

struct FileDiagnostics: Equatable {
    let url: URL
    let parentURL: URL
    let parentExists: Bool
    let parentIsWritable: Bool
    let fileExists: Bool

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.parentURL = url.deletingLastPathComponent()
        self.parentExists = fileManager.fileExists(atPath: parentURL.path)
        self.parentIsWritable = fileManager.isWritableFile(atPath: parentURL.path)
        self.fileExists = fileManager.fileExists(atPath: url.path)
    }
}

struct FileCompressionService {
    let engine: CompressionEngine
    private let fileManager: FileManager

    init(
        engine: CompressionEngine = CompressionEngineFactory.make(),
        fileManager: FileManager = .default
    ) {
        self.engine = engine
        self.fileManager = fileManager
    }

    func compressFile(
        at url: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws -> Data {
        onProgress("Reading file...", 0.1)
        let input = try Data(contentsOf: url)

        onProgress("Compressing recursively...", 0.35)
        let result = try engine.compress(input, options: .adaptive)

        onProgress("Compression complete after \(result.acceptedLayerCount) layer(s).", 1.0)
        return result.archive
    }

    func compressFile(
        at sourceURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws {
        if let rustEngine = engine as? RustHuffmanEngine {
            onProgress("Compressing with native streaming backend...", -1)
            try withTemporaryDestination(for: destinationURL) { temporaryURL in
                try rustEngine.compressFile(at: sourceURL, to: temporaryURL)
            }
            onProgress("Compression complete.", 1.0)
            return
        }

        let archive = try compressFile(at: sourceURL, onProgress: onProgress)
        try archive.write(to: destinationURL)
    }

    func decompressFile(
        at url: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws -> Data {
        onProgress("Reading archive...", 0.1)
        let archive = try Data(contentsOf: url)

        onProgress("Decompressing file...", 0.35)
        let output = try engine.decompress(archive, options: .full)

        onProgress("Decompression complete.", 1.0)
        return output
    }

    func decompressFile(
        at sourceURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (String, Double) -> Void
    ) throws {
        if let rustEngine = engine as? RustHuffmanEngine {
            onProgress("Decompressing with native streaming backend...", -1)
            try withTemporaryDestination(for: destinationURL) { temporaryURL in
                try rustEngine.decompressFile(at: sourceURL, to: temporaryURL)
            }
            onProgress("Decompression complete.", 1.0)
            return
        }

        let output = try decompressFile(at: sourceURL, onProgress: onProgress)
        try output.write(to: destinationURL)
    }

    private func withTemporaryDestination(
        for destinationURL: URL,
        write: (URL) throws -> Void
    ) throws {
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("hz-output-\(UUID().uuidString)", isDirectory: true)
        let temporaryURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw FileCompressionServiceError.temporaryDirectoryCreationFailed(
                url: temporaryDirectory,
                diagnostics: FileDiagnostics(url: temporaryDirectory, fileManager: fileManager),
                underlying: error
            )
        }

        do {
            try write(temporaryURL)
            try replaceOutput(at: destinationURL, with: temporaryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }

        do {
            try fileManager.removeItem(at: temporaryDirectory)
        } catch {
            throw FileCompressionServiceError.temporaryOutputCleanupFailed(
                url: temporaryDirectory,
                diagnostics: FileDiagnostics(url: temporaryDirectory, fileManager: fileManager),
                underlying: error
            )
        }
    }

    private func replaceOutput(at destinationURL: URL, with temporaryURL: URL) throws {
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
                return
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw FileCompressionServiceError.outputReplacementFailed(
                temporaryURL: temporaryURL,
                destinationURL: destinationURL,
                destinationDiagnostics: FileDiagnostics(url: destinationURL, fileManager: fileManager),
                temporaryDiagnostics: FileDiagnostics(url: temporaryURL, fileManager: fileManager),
                underlying: error
            )
        }
    }
}
