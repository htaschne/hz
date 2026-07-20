//
//  FileCompressionViewModelTests.swift
//  hzTests
//
//  MIT License
//  See LICENSE file for details.

import Foundation
import Testing
@testable import hz

@MainActor
struct FileCompressionViewModelTests {
    @Test func selectingRegularFilePreparesCompression() throws {
        let fileURL = try makeTemporaryFile(named: "input.txt", contents: Data("hello".utf8))
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let viewModel = FileCompressionViewModel(service: FileCompressionService(engine: SwiftHuffmanEngine()))
        viewModel.selectFile(fileURL)

        guard case let .selected(selection) = viewModel.state else {
            Issue.record("Expected selected state")
            return
        }

        #expect(selection.operation == .compress)
        #expect(selection.byteCount == 5)
        #expect(selection.suggestedOutputName == "input.txt.hz")
    }

    @Test func selectingHzArchivePreparesDecompression() throws {
        let fileURL = try makeTemporaryFile(named: "input.txt.hz", contents: Data([0x48, 0x5a]))
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let viewModel = FileCompressionViewModel(service: FileCompressionService(engine: SwiftHuffmanEngine()))
        viewModel.selectFile(fileURL)

        guard case let .selected(selection) = viewModel.state else {
            Issue.record("Expected selected state")
            return
        }

        #expect(selection.operation == .decompress)
        #expect(selection.suggestedOutputName == "input.txt")
    }

    @Test func resetClearsSelectedFile() throws {
        let fileURL = try makeTemporaryFile(named: "input.bin", contents: Data([1, 2, 3]))
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let viewModel = FileCompressionViewModel(service: FileCompressionService(engine: SwiftHuffmanEngine()))
        viewModel.selectFile(fileURL)
        viewModel.reset()

        #expect(viewModel.state == .empty)
    }

    private func makeTemporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hz-view-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL)
        return fileURL
    }
}
