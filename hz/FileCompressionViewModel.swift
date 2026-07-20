//
//  FileCompressionViewModel.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileCompressionViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var statusText: String = ""
    @Published var droppedText: String = "Drop a file here"
    @Published var isProcessing: Bool = false

    private let service: FileCompressionService

    init(service: FileCompressionService = FileCompressionService()) {
        self.service = service
    }

    func processDroppedFile(_ url: URL) {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        progress = 0
        statusText = "Loading file..."

        Task {
            do {
                if url.pathExtension.lowercased() == "hz" {
                    try await decompress(url)
                } else {
                    try await compress(url)
                }
            } catch {
                statusText = userFacingMessage(for: error)
            }

            isProcessing = false
        }
    }

    private func compress(_ url: URL) async throws {
        statusText = "Choose a location to save the compressed file..."
        guard let saveURL = showSavePanel(
            suggestedName: "\(url.lastPathComponent).hz",
            allowedFileExtensions: ["hz"]
        ) else {
            statusText = "Save cancelled."
            return
        }

        let service = self.service
        try await Task.detached(priority: .userInitiated) {
            try service.compressFile(at: url, to: saveURL) { status, progress in
                Task { @MainActor [weak self] in
                    self?.statusText = status
                    self?.progress = progress
                }
            }
        }.value

        statusText = "File saved successfully!"
    }

    private func decompress(_ url: URL) async throws {
        statusText = "Choose a location to save the decompressed file..."
        guard let saveURL = showSavePanel(
            suggestedName: decompressedFileName(for: url),
            allowedFileExtensions: nil
        ) else {
            statusText = "Save cancelled."
            return
        }

        let service = self.service
        try await Task.detached(priority: .userInitiated) {
            try service.decompressFile(at: url, to: saveURL) { status, progress in
                Task { @MainActor [weak self] in
                    self?.statusText = status
                    self?.progress = progress
                }
            }
        }.value

        statusText = "File saved successfully."
    }

    private func showSavePanel(
        suggestedName: String,
        allowedFileExtensions: [String]?
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if let allowedFileExtensions {
            panel.allowedContentTypes = allowedFileExtensions.compactMap {
                UTType(filenameExtension: $0)
            }
        }

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    private func decompressedFileName(for url: URL) -> String {
        guard url.pathExtension.lowercased() == "hz" else {
            return url.lastPathComponent
        }

        return String(url.lastPathComponent.dropLast(3))
    }

    private func userFacingMessage(for error: Error) -> String {
        if case HzArchive.Error.unsupportedLegacyArchive = error {
            return "Unsupported legacy .hz archive."
        }

        return "Failed to process file."
    }
}
