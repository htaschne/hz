//
//  Huffman.swift
//  hz
//
//  Created by Agatha Schneider on 16/04/25.
//

import AppKit
import Foundation

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

func createPriorityQueue(_ frequencies: [UInt8: Int]) -> PriorityQueue<Node> {
    var pq: PriorityQueue<Node> = PriorityQueue<Node>()

    for (char, freq) in frequencies {
        let node = Node(byte: char, count: freq)
        pq.push(node)
    }

    return pq
}

func createTree(_ pq: inout PriorityQueue<Node>) -> Node? {
    while pq.count > 1 {
        guard let lo = pq.pop() else {
            fatalError()
        }
        guard let hi = pq.pop() else {
            fatalError()
        }

        let newNode = Node(byte: 0, count: lo.count + hi.count, lo: lo, hi: hi)
        pq.push(newNode)
    }

    return pq.pop()
}

func encodeTree(root: inout Node) {
    if root.lo == nil {
        return
    }

    // Safety: we checked for nil value above and by definition,
    // of binary heap, if root.lo is not nil root.hi can't either
    root.lo?.encoding = root.encoding! + "0"
    root.hi?.encoding = root.encoding! + "1"

    encodeTree(root: &root.lo!)
    encodeTree(root: &root.hi!)
}

func traverseTree(root: inout Node, table: inout [UInt8: String]) {
    if root.lo == nil {
        table[root.byte] = root.encoding
        return
    }

    traverseTree(root: &root.lo!, table: &table)
    traverseTree(root: &root.hi!, table: &table)
}

func createTransTable(_ root: inout Node) -> [UInt8: String] {
    var table: [UInt8: String] = [:]
    traverseTree(root: &root, table: &table)
    return table
}

func compress(
    url: URL,
    updateStatus: @escaping (String) -> Void,
    updateProgress: @escaping (Double) -> Void,
    onComplete: @escaping (_ encoded: String, _ table: [UInt8: String]) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let frequencies = extractFrequencies(
            url,
            onStatusUpdate: updateStatus,
            onProgressUpdate: updateProgress
        )
        
        updateStatus("Building Huffman tree...")
        var pq = createPriorityQueue(frequencies)
        guard var root = createTree(&pq) else {
            fatalError()
        }
        
        root.encoding = ""
        encodeTree(root: &root)
        let translationTable = createTransTable(&root)
        
        updateStatus("Encoding file...")
        var encodedString = ""
        
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            
            let fileSize =
            try FileManager.default.attributesOfItem(atPath: url.path)[.size]
            as? UInt64 ?? 1
            var bytesRead: UInt64 = 0
            
            while true {
                let data = try fileHandle.read(upToCount: 4096)
                guard let byteData = data, !byteData.isEmpty else { break }
                
                for byte in byteData {
                    if let code = translationTable[byte] {
                        encodedString += code
                    }
                }
                
                bytesRead += UInt64(byteData.count)
                let progress = Double(bytesRead) / Double(fileSize)
                updateProgress(progress)
            }
            
            updateStatus("Encoding complete.")
            updateProgress(1.0)
            
            DispatchQueue.main.async {
                onComplete(encodedString, translationTable)
            }
            DispatchQueue.main.async {
                updateStatus("Choose a location to save the compressed file...")

                let panel = NSSavePanel()
                panel.allowedFileTypes = ["hz"]
                panel.nameFieldStringValue = "compressed.hz"

                if panel.runModal() == .OK, let saveURL = panel.url {
                    do {
                        try writeCompressedFile(to: saveURL, using: translationTable, and: encodedString)
                        updateStatus("File saved successfully!")
                    } catch {
                        updateStatus("Failed to save file.")
                        print("Saving error: \(error)")
                    }
                } else {
                    updateStatus("Save cancelled.")
                }
            }


            
        } catch {
            updateStatus("Error encoding file.")
            print("Encoding error: \(error)")
        }
    }
    
}


func saveCompressedFile(
    encodedBits: String,
    translationTable: [UInt8: String],
    to url: URL
) {
    var outputData = Data()

    // 1. Write number of entries in translation table
    let entryCount = UInt16(translationTable.count)
    outputData.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian, Array.init))

    // 2. Write each entry (byte, length of code, packed code bits)
    for (byte, code) in translationTable {
        outputData.append(byte)

        let bitCount = UInt8(code.count)
        outputData.append(bitCount)

        var byteBuffer: UInt8 = 0
        var bitIndex = 0

        for bitChar in code {
            if bitChar == "1" {
                byteBuffer |= (1 << (7 - bitIndex))
            }
            bitIndex += 1

            if bitIndex == 8 {
                outputData.append(byteBuffer)
                byteBuffer = 0
                bitIndex = 0
            }
        }

        if bitIndex > 0 {
            outputData.append(byteBuffer)  // Pad the last few bits
        }
    }

    // 3. Now encode the full message bits into real bytes
    var byteBuffer: UInt8 = 0
    var bitIndex = 0

    for bitChar in encodedBits {
        if bitChar == "1" {
            byteBuffer |= (1 << (7 - bitIndex))
        }
        bitIndex += 1

        if bitIndex == 8 {
            outputData.append(byteBuffer)
            byteBuffer = 0
            bitIndex = 0
        }
    }

    if bitIndex > 0 {
        outputData.append(byteBuffer)  // Pad remaining bits
    }

    // 4. Write data to file
    do {
        try outputData.write(to: url)
        print("Compressed file saved at \(url.path)")
    } catch {
        print("Failed to save file: \(error)")
    }
}

func writeCompressedFile(
    to url: URL,
    using table: [UInt8: String],
    and encodedString: String
) throws {
    var data = Data()

    // Header: number of entries in the table (UInt16)
    let entryCount = UInt16(table.count)
    data.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian, Array.init))

    // Header: each entry (byte + code length + code as bytes)
    for (byte, code) in table {
        data.append(byte)

        let bitCount = UInt8(code.count)
        data.append(bitCount)

        // Convert bit string ("10110") into bytes
        var currentByte: UInt8 = 0
        var bitIndex: UInt8 = 0

        for char in code {
            if char == "1" {
                currentByte |= (1 << (7 - bitIndex))
            }
            bitIndex += 1

            if bitIndex == 8 {
                data.append(currentByte)
                currentByte = 0
                bitIndex = 0
            }
        }

        if bitIndex > 0 {
            data.append(currentByte)
        }
    }

    // Payload: encoded binary message
    var currentByte: UInt8 = 0
    var bitIndex: UInt8 = 0

    for bitChar in encodedString {
        if bitChar == "1" {
            currentByte |= (1 << (7 - bitIndex))
        }
        bitIndex += 1

        if bitIndex == 8 {
            data.append(currentByte)
            currentByte = 0
            bitIndex = 0
        }
    }

    if bitIndex > 0 {
        data.append(currentByte)
    }

    try data.write(to: url)
}
