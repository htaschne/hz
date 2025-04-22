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
    @State private var progress: Double = 0.0
    @State private var statusText: String = ""
    @State private var droppedText: String = "Drop a file here"
    @State private var isProcessing: Bool = false

    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)

            if isProcessing {
                VStack(spacing: 20) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 250)
                        .animation(.easeInOut(duration: 0.25), value: progress)

                    HStack {
                        Text(statusText)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
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
                    Text(droppedText)
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
                            // Update state to show progress bar
                            self.isProcessing = true
                            self.progress = 0
                            self.statusText = "Loading file..."

                            // Common completion handler
                            let finish: () -> Void = {
                                DispatchQueue.main.async {
                                    self.isProcessing = false
                                }
                            }

                            if url.pathExtension.lowercased() == "hz" {
                                decompress(
                                    url: url,
                                    updateStatus: { self.statusText = $0 },
                                    updateProgress: { self.progress = $0 },
                                    onFinish: finish
                                )
                            } else {
                                compress(
                                    url: url,
                                    updateStatus: { self.statusText = $0 },
                                    updateProgress: { self.progress = $0 },
                                    onFinish: finish
                                )
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }

}
