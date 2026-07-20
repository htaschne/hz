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
                technicalDetails: technicalDetails(for: error),
                sourceURL: sourceURL
            )
        }

        if let serviceError = error as? FileCompressionServiceError {
            return OperationFailure(
                title: "Output File Could Not Be Created",
                message: "Choose another destination or verify that the folder is writable.",
                technicalDetails: technicalDetails(for: serviceError),
                sourceURL: sourceURL
            )
        }

        if let nativeError = error as? NativeEngineError {
            return OperationFailure(
                title: nativeErrorTitle(nativeError, operation: operation),
                message: nativeErrorMessage(nativeError),
                technicalDetails: technicalDetails(for: nativeError),
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
            technicalDetails: technicalDetails(for: error),
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
            let .unknownStatus(_, message):
            return message.isEmpty ? "The native backend returned an error." : message
        case .allocationFailed:
            return "The native backend could not allocate enough memory."
        case let .internalError(message):
            if message.contains("destination") || message.contains("output") || message.contains("file") {
                return "Choose another destination or verify that the folder is writable."
            }

            return message.isEmpty ? "The native backend returned an error." : message
        }
    }

    private static func technicalDetails(for error: Error) -> String {
        #if DEBUG
        return debugTechnicalDetails(for: error)
        #else
        return releaseTechnicalDetails(for: error)
        #endif
    }

    private static func releaseTechnicalDetails(for error: Error) -> String {
        if error is FileCompressionServiceError {
            return "Output file creation or replacement failed."
        }

        if let nativeError = error as? NativeEngineError {
            switch nativeError {
            case .unavailable:
                return "Native backend unavailable."
            case .notImplemented:
                return "Native backend operation is not implemented."
            case .invalidArgument:
                return "Native backend rejected the input."
            case .allocationFailed:
                return "Native backend allocation failed."
            case .internalError:
                return "Native backend file operation failed."
            case let .unknownStatus(status, _):
                return "Native backend returned status \(status)."
            }
        }

        return String(describing: error)
    }

    #if DEBUG
    private static func debugTechnicalDetails(for error: Error) -> String {
        if let serviceError = error as? FileCompressionServiceError {
            return debugServiceDetails(for: serviceError)
        }

        let nsError = error as NSError
        return """
        Error: \(String(describing: error))
        Domain: \(nsError.domain)
        Code: \(nsError.code)
        Description: \(nsError.localizedDescription)
        """
    }

    private static func debugServiceDetails(for error: FileCompressionServiceError) -> String {
        switch error {
        case let .temporaryDirectoryCreationFailed(url, diagnostics, underlying):
            return """
            Category: temporary directory creation failed
            Operation: createDirectory
            URL: \(url.path)
            \(debugDiagnostics(diagnostics))
            \(debugUnderlyingError(underlying))
            """
        case let .temporaryOutputCleanupFailed(url, diagnostics, underlying):
            return """
            Category: temporary output cleanup failed
            Operation: removeItem
            URL: \(url.path)
            \(debugDiagnostics(diagnostics))
            \(debugUnderlyingError(underlying))
            """
        case let .outputReplacementFailed(
            temporaryURL,
            destinationURL,
            destinationDiagnostics,
            temporaryDiagnostics,
            underlying
        ):
            return """
            Category: output replacement failed
            Operation: replaceItemAt or moveItem
            Temporary URL: \(temporaryURL.path)
            Destination URL: \(destinationURL.path)
            Destination diagnostics:
            \(debugDiagnostics(destinationDiagnostics))
            Temporary diagnostics:
            \(debugDiagnostics(temporaryDiagnostics))
            \(debugUnderlyingError(underlying))
            """
        }
    }

    private static func debugDiagnostics(_ diagnostics: FileDiagnostics) -> String {
        """
        URL: \(diagnostics.url.path)
        Parent: \(diagnostics.parentURL.path)
        Parent exists: \(diagnostics.parentExists)
        Parent writable: \(diagnostics.parentIsWritable)
        File exists: \(diagnostics.fileExists)
        """
    }

    private static func debugUnderlyingError(_ error: Error) -> String {
        let nsError = error as NSError
        return """
        Underlying error: \(String(describing: error))
        Domain: \(nsError.domain)
        Code: \(nsError.code)
        Description: \(nsError.localizedDescription)
        """
    }
    #endif
}
