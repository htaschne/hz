//
//  FileCompressionViewModel.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FileCompressionViewModel: ObservableObject {
    @Published private(set) var state: FileCompressionState = .empty
    @Published var isDropTargeted = false

    private let service: FileCompressionService
    private let fileManager: FileManager

    init(
        service: FileCompressionService? = nil,
        fileManager: FileManager = .default
    ) {
        self.service = service ?? Self.makeDefaultService()
        self.fileManager = fileManager
    }

    func selectFile(_ url: URL) {
        guard !isProcessing else {
            return
        }

        let standardizedURL = url.standardizedFileURL
        let operation = Self.operation(for: standardizedURL)
        let byteCount = Self.fileSize(at: standardizedURL, fileManager: fileManager)

        state = .selected(
            SelectedFile(
                url: standardizedURL,
                operation: operation,
                byteCount: byteCount
            )
        )
    }

    func reset() {
        guard !isProcessing else {
            return
        }

        state = .empty
    }

    func startSelectedOperation() {
        guard case let .selected(selection) = state else {
            return
        }

        Task {
            await process(selection)
        }
    }

    func chooseAnotherFile() {
        reset()
    }

    func revealResultInFinder() {
        guard case let .success(result) = state else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([result.destinationURL])
    }

    func openResultFolder() {
        guard case let .success(result) = state else {
            return
        }

        NSWorkspace.shared.open(result.destinationURL.deletingLastPathComponent())
    }

    private var isProcessing: Bool {
        if case .processing = state {
            return true
        }

        return false
    }

    private func process(_ selection: SelectedFile) async {
        guard let destinationURL = showSavePanel(for: selection) else {
            return
        }

        let progress = OperationProgress(
            operation: selection.operation,
            sourceURL: selection.url,
            destinationURL: destinationURL,
            message: "\(selection.operation.runningTitle) \(selection.url.lastPathComponent)...",
            fractionCompleted: nil
        )
        state = .processing(progress)

        let start = Date()
        let sourceURL = selection.url
        let sourceAccessGranted = sourceURL.startAccessingSecurityScopedResource()
        let destinationAccessGranted = destinationURL.startAccessingSecurityScopedResource()

        defer {
            if sourceAccessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            if destinationAccessGranted {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let service = self.service
            try await Task.detached(priority: .userInitiated) {
                switch selection.operation {
                case .compress:
                    try service.compressFile(at: sourceURL, to: destinationURL) { status, progress in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(
                                status,
                                progress: progress,
                                operation: selection.operation,
                                sourceURL: sourceURL,
                                destinationURL: destinationURL
                            )
                        }
                    }
                case .decompress:
                    try service.decompressFile(at: sourceURL, to: destinationURL) { status, progress in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(
                                status,
                                progress: progress,
                                operation: selection.operation,
                                sourceURL: sourceURL,
                                destinationURL: destinationURL
                            )
                        }
                    }
                }
            }.value

            state = .success(
                OperationResult(
                    operation: selection.operation,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    inputByteCount: selection.byteCount ?? Self.fileSize(at: sourceURL, fileManager: fileManager),
                    outputByteCount: Self.fileSize(at: destinationURL, fileManager: fileManager),
                    elapsedTime: Date().timeIntervalSince(start)
                )
            )
        } catch {
            state = .failure(Self.failure(from: error, operation: selection.operation, sourceURL: sourceURL))
        }
    }

    private func updateProgress(
        _ message: String,
        progress: Double,
        operation: FileOperation,
        sourceURL: URL,
        destinationURL: URL
    ) {
        guard case .processing = state else {
            return
        }

        let fractionCompleted = progress >= 0 ? min(max(progress, 0), 1) : nil
        state = .processing(
            OperationProgress(
                operation: operation,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: message,
                fractionCompleted: fractionCompleted
            )
        )
    }

    private func showSavePanel(for selection: SelectedFile) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = selection.suggestedOutputName
        panel.directoryURL = selection.url.deletingLastPathComponent()

        if selection.operation == .compress {
            panel.allowedContentTypes = [UTType(filenameExtension: "hz") ?? .data]
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func makeDefaultService() -> FileCompressionService {
        let rustInfo = RustHuffmanEngine.info
        if rustInfo.isBridgeAvailable, rustInfo.supportsCompression {
            return FileCompressionService(engine: RustHuffmanEngine())
        }

        return FileCompressionService()
    }

    private static func operation(for url: URL) -> FileOperation {
        if url.pathExtension.caseInsensitiveCompare("hz") == .orderedSame {
            return .decompress
        }

        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
            type.conforms(to: UTType(filenameExtension: "hz") ?? .data) {
            return .decompress
        }

        return .compress
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }

        return fileSize.int64Value
    }

    private static func failure(
        from error: Error,
        operation: FileOperation,
        sourceURL: URL
    ) -> OperationFailure {
        if case HzArchive.Error.unsupportedLegacyArchive = error {
            return OperationFailure(
                title: "Unsupported Archive",
                message: "This file uses the old .hz format and cannot be decoded by the current app.",
                technicalDetails: String(describing: error),
                sourceURL: sourceURL
            )
        }

        if operation == .decompress, isArchiveDecodingError(error) {
            return OperationFailure(
                title: "Archive Could Not Be Decoded",
                message: "The selected .hz file is corrupt, incomplete, or not a supported Hz archive.",
                technicalDetails: String(describing: error),
                sourceURL: sourceURL
            )
        }

        if let nativeError = error as? NativeEngineError {
            return OperationFailure(
                title: nativeErrorTitle(nativeError, operation: operation),
                message: nativeErrorMessage(nativeError),
                technicalDetails: String(describing: nativeError),
                sourceURL: sourceURL
            )
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return OperationFailure(
                title: "File Could Not Be Written",
                message: nsError.localizedDescription,
                technicalDetails: "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)",
                sourceURL: sourceURL
            )
        }

        return OperationFailure(
            title: "\(operation.title) Failed",
            message: "Hz could not finish this operation.",
            technicalDetails: String(describing: error),
            sourceURL: sourceURL
        )
    }

    private static func isArchiveDecodingError(_ error: Error) -> Bool {
        if error is HzArchive.Error || error is HuffmanCodecError || error is HuffmanTreeError {
            return true
        }

        if case NativeEngineError.invalidArgument = error {
            return true
        }

        return false
    }

    private static func nativeErrorTitle(
        _ error: NativeEngineError,
        operation: FileOperation
    ) -> String {
        switch error {
        case .unavailable:
            return "Native Backend Unavailable"
        case .notImplemented:
            return "Native Backend Incomplete"
        default:
            return "\(operation.title) Failed"
        }
    }

    private static func nativeErrorMessage(_ error: NativeEngineError) -> String {
        switch error {
        case .unavailable:
            return "The native Rust backend is not available in this build."
        case let .notImplemented(message),
            let .invalidArgument(message),
            let .allocationFailed(message),
            let .internalError(message),
            let .unknownStatus(_, message):
            return message.isEmpty ? "The native backend returned an error." : message
        }
    }
}
