//
//  ContentView.swift
//  hz
//
//  Created by Agatha Schneider on 16/04/25.
//

import AppKit
import SwiftUI

func showSavePanel(
    suggestedFileName: String,
    completion: @escaping (URL?) -> Void
) {
    let panel = NSSavePanel()
    panel.title = "Save Compressed File"
    panel.allowedFileTypes = ["hz"]
    panel.nameFieldStringValue = suggestedFileName

    panel.begin { result in
        if result == .OK {
            completion(panel.url)
        } else {
            completion(nil)
        }
    }
}

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
            if let provider = providers.first {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        DispatchQueue.main.async {
                            isProcessing = true
                            droppedText =
                                "Dropped file: \(url.lastPathComponent)"
                            statusText = "Compressing..."
                            progress = 0

                            compress(
                                url: url,
                                updateStatus: { message in
                                    DispatchQueue.main.async {
                                        statusText = message
                                        if message.contains("complete")
                                            || message.contains("Error")
                                        {
                                            isProcessing = false
                                        }
                                    }
                                },
                                updateProgress: { p in
                                    DispatchQueue.main.async {
                                        progress = p
                                    }
                                },
                                onComplete: { encoded, table in
                                    showSavePanel(
                                        suggestedFileName:
                                            url.deletingPathExtension()
                                            .lastPathComponent + ".hz"
                                    ) { selectedURL in
                                        if let saveURL = selectedURL {
                                            saveCompressedFile(
                                                encodedBits: encoded,
                                                translationTable: table,
                                                to: saveURL
                                            )
                                            DispatchQueue.main.async {
                                                statusText =
                                                    "File saved successfully!"
                                            }
                                        } else {
                                            DispatchQueue.main.async {
                                                statusText = "Save canceled."
                                            }
                                        }
                                    }
                                }
                            )

                        }
                    }
                }
                return true
            }
            return false
        }
    }
}
