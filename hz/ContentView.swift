//
//  ContentView.swift
//  hz
//
//  Created by Agatha Schneider on 16/04/25.
//

import SwiftUI

struct ContentView: View {
    @State private var droppedText: String = "Drop a file here"
    @State private var statusMessage: String = ""
    @State private var isProcessing = false
    @State private var progress: Double = 0.0  // between 0 and 1

    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)

            if isProcessing {
                VStack(spacing: 20) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 250)

                    HStack {
                        Text(statusMessage)
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
                            statusMessage = "Starting compression..."
                            progress = 0

                            compress(
                                url: url,
                                updateStatus: { message in
                                    DispatchQueue.main.async {
                                        statusMessage = message
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
