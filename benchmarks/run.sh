#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
RUNNER="$BUILD_DIR/hz-benchmark"

mkdir -p "$BUILD_DIR"

swiftc -O \
  "$REPO_ROOT/hz/BitReader.swift" \
  "$REPO_ROOT/hz/BitWriter.swift" \
  "$REPO_ROOT/hz/CompressionEngine.swift" \
  "$REPO_ROOT/hz/FrequencyTable.swift" \
  "$REPO_ROOT/hz/HuffmanCodec.swift" \
  "$REPO_ROOT/hz/HuffmanTree.swift" \
  "$REPO_ROOT/hz/HzArchive.swift" \
  "$REPO_ROOT/hz/RecursiveCompressionController.swift" \
  "$REPO_ROOT/hz/SwiftHuffmanEngine.swift" \
  "$SCRIPT_DIR/Sources/main.swift" \
  -o "$RUNNER"

"$RUNNER" "$@"

