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

struct ContentView: View {
    @StateObject private var viewModel = FileCompressionViewModel()

    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)

            if viewModel.isProcessing {
                VStack(spacing: 20) {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 250)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.progress)

                    HStack {
                        Text(viewModel.statusText)
                        Spacer()
                        Text(String(format: "%.0f%%", viewModel.progress * 100))
                            .monospacedDigit()
                    }
                    .frame(width: 250)
                    .foregroundColor(.gray)
                }
            } else {
                VStack {
                    Image("drag&drop")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 300)
                    Text(viewModel.droppedText)
                        .padding(.top, 8)
                        .foregroundColor(.black)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            return handleDrop(providers: providers)
        }
    }
}

extension ContentView {
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(
                    forTypeIdentifier: "public.file-url",
                    options: nil
                ) { item, error in
                    DispatchQueue.main.async {
                        if let data = item as? Data,
                            let url = URL(
                                dataRepresentation: data,
                                relativeTo: nil
                            )
                        {
                            viewModel.processDroppedFile(url)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

}
