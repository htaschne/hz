//
//  FileCompressionStateViews.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation
import SwiftUI

struct EmptyStateView: View {
    let isDropTargeted: Bool
    let chooseFile: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "archivebox")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Drop a file to compress or decompress")
                    .font(.title3.weight(.semibold))
                Text("Files ending in .hz are decompressed. Other files are compressed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                chooseFile()
            } label: {
                Label("Choose File", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityLabel("Choose File")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.32),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7, 7])
                )
                .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        }
        .accessibilityElement(children: .contain)
    }
}

struct SelectedStateView: View {
    let selection: SelectedFile
    let start: () -> Void
    let chooseAnother: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            FileSummaryHeader(
                iconName: selection.operation == .compress ? "doc" : "archivebox",
                title: selection.url.lastPathComponent,
                subtitle: selection.url.deletingLastPathComponent().path,
                status: selection.operation.title
            )

            Divider()

            DetailGrid {
                DetailRow(label: "Input", value: ByteCountFormatter.hzString(from: selection.byteCount))
                DetailRow(label: "Output", value: selection.suggestedOutputName)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Clear", role: .cancel) {
                    clear()
                }
                .accessibilityLabel("Clear Selection")

                Button {
                    chooseAnother()
                } label: {
                    Label("Choose Another", systemImage: "folder")
                }
                .accessibilityLabel("Choose Another File")

                Spacer()

                Button {
                    start()
                } label: {
                    Label(selection.operation.title, systemImage: selection.operation == .compress ? "archivebox" : "arrow.up.doc")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel(selection.operation.title)
            }
        }
    }
}

struct ProcessingStateView: View {
    let progress: OperationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            FileSummaryHeader(
                iconName: progress.operation == .compress ? "archivebox" : "arrow.up.doc",
                title: progress.operation.runningTitle,
                subtitle: progress.sourceURL.lastPathComponent,
                status: "In Progress"
            )

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                        .accessibilityValue("\(Int(fraction * 100)) percent")
                    HStack {
                        Text(progress.message)
                        Spacer()
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel(progress.message)
                    Text(progress.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            DetailGrid {
                DetailRow(label: "Destination", value: progress.destinationURL.lastPathComponent)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct SuccessStateView: View {
    let result: OperationResult
    let reveal: () -> Void
    let openFolder: () -> Void
    let newOperation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            FileSummaryHeader(
                iconName: "checkmark.circle.fill",
                title: "\(result.operation.completedTitle) Successfully",
                subtitle: result.destinationURL.lastPathComponent,
                status: "Complete",
                iconColor: .green
            )

            Divider()

            DetailGrid {
                DetailRow(label: "Input", value: ByteCountFormatter.hzString(from: result.inputByteCount))
                DetailRow(label: "Output", value: ByteCountFormatter.hzString(from: result.outputByteCount))
                DetailRow(label: "Elapsed", value: result.elapsedTime.hzDurationString)
                if let byteDelta = result.byteDelta, result.operation == .compress {
                    DetailRow(label: "Delta", value: ByteCountFormatter.hzSignedString(from: byteDelta))
                }
                DetailRow(label: "Saved As", value: result.destinationURL.path)
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    newOperation()
                } label: {
                    Label("Another File", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Start Another Operation")

                Spacer()

                Button {
                    openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .accessibilityLabel("Open Output Folder")

                Button {
                    reveal()
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Reveal Output in Finder")
            }
        }
    }
}

struct FailureStateView: View {
    let failure: OperationFailure
    let chooseFile: () -> Void
    let newOperation: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            FileSummaryHeader(
                iconName: "exclamationmark.triangle.fill",
                title: failure.title,
                subtitle: failure.message,
                status: "Failed",
                iconColor: .orange
            )

            if !failure.technicalDetails.isEmpty {
                DisclosureGroup("Details", isExpanded: $showsDetails) {
                    Text(failure.technicalDetails)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    newOperation()
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .accessibilityLabel("Clear Error")

                Spacer()

                Button {
                    chooseFile()
                } label: {
                    Label("Choose File", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Choose Another File")
            }
        }
    }
}

private struct FileSummaryHeader: View {
    let iconName: String
    let title: String
    let subtitle: String
    let status: String
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct DetailGrid<Rows: View>: View {
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            rows()
        }
        .font(.callout)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private extension ByteCountFormatter {
    static func hzString(from byteCount: Int64?) -> String {
        guard let byteCount else {
            return "Unknown"
        }

        return string(fromByteCount: byteCount, countStyle: .file)
    }

    static func hzSignedString(from byteCount: Int64) -> String {
        let formatted = string(fromByteCount: abs(byteCount), countStyle: .file)
        if byteCount > 0 {
            return "\(formatted) smaller"
        }
        if byteCount < 0 {
            return "\(formatted) larger"
        }

        return "No change"
    }
}

private extension TimeInterval {
    var hzDurationString: String {
        if self < 1 {
            return "<1s"
        }

        return "\(Int(rounded()))s"
    }
}
