import Foundation

struct BenchmarkOptions {
    var inputPath: String?
    var workloadsPath = "benchmarks/workloads/generated"
    var outputPath = "benchmarks/results"
    var maxAdditionalDepth: Int?
    var engineKind = BenchmarkEngineKind.swift
}

enum BenchmarkEngineKind: String {
    case swift
    case rust
}

struct Workload {
    let name: String
    let url: URL
}

enum BenchmarkError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidArgument(String)
    case noWorkloads
    case verificationFailed(String)
    case rustEngineUnavailable

    var description: String {
        switch self {
        case .missingValue(let argument):
            return "Missing value for \(argument)"
        case .invalidArgument(let argument):
            return "Invalid argument: \(argument)"
        case .noWorkloads:
            return "No workloads found"
        case .verificationFailed(let workload):
            return "Verification failed for \(workload)"
        case .rustEngineUnavailable:
            return "Rust benchmark engine was selected, but the runner was not built with HZ_NATIVE_BRIDGE"
        }
    }
}

let startDate = Date()

do {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))

    if options.engineKind == .rust {
        try runRustBridgeProbe()
    }

    let fileManager = FileManager.default
    let outputURL = URL(fileURLWithPath: options.outputPath)
    let rawURL = outputURL.appendingPathComponent("raw", isDirectory: true)
    let csvURL = outputURL.appendingPathComponent("csv", isDirectory: true)

    try fileManager.createDirectory(at: rawURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: csvURL, withIntermediateDirectories: true)

    let workloads = try loadWorkloads(options: options)
    guard !workloads.isEmpty else {
        throw BenchmarkError.noWorkloads
    }

    let mode = options.maxAdditionalDepth == nil
        ? "adaptive"
        : (options.maxAdditionalDepth == 0 ? "baseline" : "forced")
    let configuredDepth = options.maxAdditionalDepth.map(String.init) ?? "adaptive"

    var passRows = [
        "workload,mode,configured_max_depth,pass,input_bytes,output_bytes,ratio,accepted,best_pass,accepted_layer_count,stopping_reason,compression_seconds,decompression_seconds,verified"
    ]
    var summaryRows = [
        "workload,mode,configured_max_depth,original_bytes,final_archive_bytes,best_pass,best_archive_bytes,accepted_layer_count,stopping_reason,compression_seconds,decompression_seconds,verified,platform"
    ]

    let engine = SwiftHuffmanEngine()

    for workload in workloads {
        let original = try Data(contentsOf: workload.url)
        let compressionOptions = CompressionOptions(
            maxAdditionalDepth: options.maxAdditionalDepth,
            stopWhenNotSmaller: options.maxAdditionalDepth == nil
        )

        let compressionStart = Date()
        let result = try engine.compress(original, options: compressionOptions)
        let compressionSeconds = Date().timeIntervalSince(compressionStart)

        let decompressionStart = Date()
        let decompressed = try engine.decompress(result.archive, options: .full)
        let decompressionSeconds = Date().timeIntervalSince(decompressionStart)
        let verified = decompressed == original

        guard verified else {
            throw BenchmarkError.verificationFailed(workload.name)
        }

        let archiveURL = rawURL.appendingPathComponent("\(workload.name)-\(mode).hz")
        try result.archive.write(to: archiveURL)

        let bestPass = result.bestPass
        for pass in result.passes {
            passRows.append(
                [
                    csv(workload.name),
                    mode,
                    configuredDepth,
                    String(pass.layer),
                    String(pass.inputByteCount),
                    String(pass.outputByteCount),
                    format(pass.ratio),
                    String(pass.accepted),
                    String(bestPass?.layer ?? 0),
                    String(result.acceptedLayerCount),
                    result.stoppingReason.rawValue,
                    format(compressionSeconds),
                    format(decompressionSeconds),
                    String(verified)
                ].joined(separator: ",")
            )
        }

        summaryRows.append(
            [
                csv(workload.name),
                mode,
                configuredDepth,
                String(original.count),
                String(result.archive.count),
                String(bestPass?.layer ?? 0),
                String(bestPass?.outputByteCount ?? result.archive.count),
                String(result.acceptedLayerCount),
                result.stoppingReason.rawValue,
                format(compressionSeconds),
                format(decompressionSeconds),
                String(verified),
                csv(platformDescription())
            ].joined(separator: ",")
        )
    }

    let stamp = timestamp(startDate)
    let passURL = csvURL.appendingPathComponent("passes-\(mode)-\(stamp).csv")
    let summaryURL = csvURL.appendingPathComponent("summary-\(mode)-\(stamp).csv")
    try passRows.joined(separator: "\n").write(to: passURL, atomically: true, encoding: .utf8)
    try summaryRows.joined(separator: "\n").write(to: summaryURL, atomically: true, encoding: .utf8)

    print("Wrote \(passURL.path)")
    print("Wrote \(summaryURL.path)")
} catch {
    fputs("benchmark error: \(error)\n", stderr)
    exit(1)
}

func parseArguments(_ arguments: [String]) throws -> BenchmarkOptions {
    var options = BenchmarkOptions()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--input":
            options.inputPath = try value(after: argument, in: arguments, at: &index)
        case "--workloads":
            options.workloadsPath = try value(after: argument, in: arguments, at: &index)
        case "--output":
            options.outputPath = try value(after: argument, in: arguments, at: &index)
        case "--engine":
            let rawValue = try value(after: argument, in: arguments, at: &index)
            guard let engineKind = BenchmarkEngineKind(rawValue: rawValue) else {
                throw BenchmarkError.invalidArgument(argument)
            }
            options.engineKind = engineKind
        case "--max-depth":
            let rawValue = try value(after: argument, in: arguments, at: &index)
            guard let depth = Int(rawValue), depth >= 0 else {
                throw BenchmarkError.invalidArgument(argument)
            }
            options.maxAdditionalDepth = depth
        case "--adaptive":
            options.maxAdditionalDepth = nil
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw BenchmarkError.invalidArgument(argument)
        }

        index += 1
    }

    return options
}

func runRustBridgeProbe() throws -> Never {
    #if HZ_NATIVE_BRIDGE
    let info = RustHuffmanEngine.info
    print("Rust bridge available: \(info.isBridgeAvailable)")
    print("Rust native ABI version: \(info.abiVersion)")
    print("Rust native version: \(info.version)")
    print("Rust Huffman compression supported: \(info.supportsCompression)")

    do {
        _ = try RustHuffmanEngine().compress(Data(), options: .singlePass)
        fputs("benchmark error: Rust Huffman engine unexpectedly produced output\n", stderr)
        exit(3)
    } catch NativeEngineError.notImplemented(let message) {
        fputs("benchmark error: Rust Huffman engine not implemented: \(message)\n", stderr)
        exit(2)
    } catch {
        fputs("benchmark error: Rust bridge failed: \(error)\n", stderr)
        exit(1)
    }
    #else
    throw BenchmarkError.rustEngineUnavailable
    #endif
}

func value(after argument: String, in arguments: [String], at index: inout Int) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
        throw BenchmarkError.missingValue(argument)
    }

    index = valueIndex
    return arguments[valueIndex]
}

func loadWorkloads(options: BenchmarkOptions) throws -> [Workload] {
    if let inputPath = options.inputPath {
        let url = URL(fileURLWithPath: inputPath)
        return [Workload(name: sanitizedName(url.deletingPathExtension().lastPathComponent), url: url)]
    }

    let workloadsURL = URL(fileURLWithPath: options.workloadsPath)
    try generateWorkloads(in: workloadsURL)

    return try FileManager.default
        .contentsOfDirectory(at: workloadsURL, includingPropertiesForKeys: nil)
        .filter { !$0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { Workload(name: sanitizedName($0.deletingPathExtension().lastPathComponent), url: $0) }
}

func generateWorkloads(in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    try Data(String(repeating: "aaaaabbbbbcccccdddddeeeee\n", count: 512).utf8)
        .write(to: directory.appendingPathComponent("repetitive-text.txt"))

    let prose = """
    Huffman coding assigns shorter bit patterns to symbols that appear more often.
    This workload is intentionally plain prose with uneven letter frequencies,
    punctuation, spaces, and repeated words. It is small enough to commit and
    deterministic enough for repeatable benchmark comparisons.
    """
    try Data(String(repeating: prose + "\n", count: 80).utf8)
        .write(to: directory.appendingPathComponent("ordinary-prose.txt"))

    try Data(repeating: 0x41, count: 16_384)
        .write(to: directory.appendingPathComponent("single-byte.bin"))

    try deterministicBytes(count: 16_384, seed: 0x1234_5678_9ABC_DEF0)
        .write(to: directory.appendingPathComponent("high-entropy.bin"))

    try compressedLikeBytes(count: 16_384)
        .write(to: directory.appendingPathComponent("compressed-like.bin"))
}

func deterministicBytes(count: Int, seed: UInt64) -> Data {
    var state = seed
    var bytes: [UInt8] = []
    bytes.reserveCapacity(count)

    for _ in 0..<count {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        bytes.append(UInt8(truncatingIfNeeded: state >> 56))
    }

    return Data(bytes)
}

func compressedLikeBytes(count: Int) -> Data {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(count)
    var state: UInt64 = 0xCAFE_BABE_DEAD_BEEF

    while bytes.count < count {
        state = state &* 2862933555777941757 &+ 3037000493
        bytes.append(UInt8(truncatingIfNeeded: state >> 40))
        if bytes.count % 31 == 0 {
            bytes.append(0)
        }
    }

    return Data(bytes.prefix(count))
}

func sanitizedName(_ name: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    let scalars = name.unicodeScalars.map { allowed.contains(Character($0)) ? Character($0) : "-" }
    return String(scalars)
}

func format(_ value: Double) -> String {
    String(format: "%.9f", value)
}

func csv(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    return value
}

func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

func platformDescription() -> String {
    let info = ProcessInfo.processInfo
    return "\(info.operatingSystemVersionString); processors=\(info.processorCount)"
}

func printUsage() {
    print(
        """
        Usage:
          benchmarks/run.sh [--adaptive]
          benchmarks/run.sh --engine swift [--adaptive]
          benchmarks/run.sh --engine rust
          benchmarks/run.sh --max-depth 0
          benchmarks/run.sh --max-depth N
          benchmarks/run.sh --input path/to/file [--max-depth N]

        Options:
          --engine NAME      Engine to use: swift or rust. Defaults to swift.
          --input PATH       Benchmark one file.
          --workloads PATH   Benchmark all files in a workload directory.
          --output PATH      Results directory. Defaults to benchmarks/results.
          --adaptive         Stop before the first non-smaller recursive layer.
          --max-depth N      Force N additional passes after the first pass.
        """
    )
}
