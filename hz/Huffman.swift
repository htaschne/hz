//
//  Huffman.swift
//  hz
//
//  Created by Agatha Schneider on 16/04/25.
//

import Foundation

func compress(
    url: URL,
    updateStatus: @escaping (String) -> Void,
    updateProgress: @escaping (Double) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let _ = extractFrequencies(
            url,
            onStatusUpdate: updateStatus,
            onProgressUpdate: updateProgress
        )

        updateStatus("Compression done.")
        updateProgress(1.0)
    }
}

func extractFrequencies(
    _ url: URL,
    onStatusUpdate: @escaping (String) -> Void,
    onProgressUpdate: @escaping (Double) -> Void
) -> [UInt8: Int] {

    onStatusUpdate("Calculating frequencies...")
    var counter: [UInt8: Int] = [:]

    do {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize =
            try FileManager.default.attributesOfItem(atPath: url.path)[.size]
            as? UInt64 ?? 1
        var bytesRead: UInt64 = 0

        while true {
            let data = try fileHandle.read(upToCount: 4096)  // read in chunks
            guard let byteData = data, !byteData.isEmpty else { break }

            for byte in byteData {
                counter.updateValue((counter[byte] ?? 0) + 1, forKey: byte)
            }

            bytesRead += UInt64(byteData.count)
            let progress = Double(bytesRead) / Double(fileSize)
            onProgressUpdate(progress)
        }

        onStatusUpdate("Frequency calculation complete.")

    } catch {
        onStatusUpdate("Error reading file.")
        print("Error: \(error)")
    }

    return counter
}
