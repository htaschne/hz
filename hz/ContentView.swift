//
//  ContentView.swift
//  hz
//
//  Created by Agatha Schneider on 16/04/25.
//
//  MIT License
//  See LICENSE file for details.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = FileCompressionViewModel()
    @State private var isImporterPresented = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Choose File", systemImage: "folder")
                }
                .help("Choose a file")
                .accessibilityLabel("Choose File")

                Button {
                    viewModel.reset()
                } label: {
                    Label("New Operation", systemImage: "plus")
                }
                .help("Start a new operation")
                .accessibilityLabel("New Operation")
                .disabled(!canReset)

                Button {
                    viewModel.revealResultInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .help("Reveal the output file in Finder")
                .accessibilityLabel("Reveal Output in Finder")
                .disabled(!hasResult)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $viewModel.isDropTargeted
        ) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hzOpenFileCommand)) { _ in
            isImporterPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .hzNewOperationCommand)) { _ in
            viewModel.reset()
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModel.state.phaseID)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            EmptyStateView(isDropTargeted: viewModel.isDropTargeted) {
                isImporterPresented = true
            }
        case let .selected(selection):
            SelectedStateView(selection: selection) {
                viewModel.startSelectedOperation()
            } chooseAnother: {
                isImporterPresented = true
            } clear: {
                viewModel.reset()
            }
        case let .processing(progress):
            ProcessingStateView(progress: progress)
        case let .success(result):
            SuccessStateView(result: result) {
                viewModel.revealResultInFinder()
            } openFolder: {
                viewModel.openResultFolder()
            } newOperation: {
                viewModel.reset()
            }
        case let .failure(failure):
            FailureStateView(failure: failure) {
                isImporterPresented = true
            } newOperation: {
                viewModel.reset()
            }
        }
    }

    private var canReset: Bool {
        switch viewModel.state {
        case .empty, .processing:
            false
        case .selected, .success, .failure:
            true
        }
    }

    private var hasResult: Bool {
        if case .success = viewModel.state {
            return true
        }

        return false
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }

            viewModel.selectFile(url)
        case .failure:
            return
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let droppedURL = item as? URL {
                url = droppedURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            guard let url else {
                return
            }

            DispatchQueue.main.async {
                viewModel.selectFile(url)
            }
        }

        return true
    }
}
