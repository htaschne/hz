#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
RUNNER="$BUILD_DIR/hz-benchmark"
ENGINE="swift"

for ((index = 1; index <= $#; index++)); do
  if [[ "${!index}" == "--engine" ]]; then
    next=$((index + 1))
    if [[ $next -le $# ]]; then
      ENGINE="${!next}"
    fi
  fi
done

mkdir -p "$BUILD_DIR"

COMMON_SOURCES=(
  "$REPO_ROOT/hz/BitReader.swift"
  "$REPO_ROOT/hz/BitWriter.swift"
  "$REPO_ROOT/hz/CompressionEngine.swift"
  "$REPO_ROOT/hz/FrequencyTable.swift"
  "$REPO_ROOT/hz/HuffmanCodec.swift"
  "$REPO_ROOT/hz/HuffmanTree.swift"
  "$REPO_ROOT/hz/HzArchive.swift"
  "$REPO_ROOT/hz/RecursiveCompressionController.swift"
  "$REPO_ROOT/hz/SwiftHuffmanEngine.swift"
)

case "$ENGINE" in
  swift)
    swiftc -O \
      "${COMMON_SOURCES[@]}" \
      "$SCRIPT_DIR/Sources/main.swift" \
      -o "$RUNNER"
    ;;
  rust)
    "$REPO_ROOT/scripts/native/build.sh" Release
    swiftc -O \
      -D HZ_NATIVE_BRIDGE \
      -I "$REPO_ROOT/native" \
      -L "$REPO_ROOT/native/hz-native/target/aarch64-apple-darwin/release" \
      "${COMMON_SOURCES[@]}" \
      "$REPO_ROOT/hz/NativeEngineError.swift" \
      "$REPO_ROOT/hz/RustHuffmanEngine.swift" \
      "$SCRIPT_DIR/Sources/main.swift" \
      -lhz_native \
      -o "$RUNNER"
    ;;
  *)
    echo "error: unsupported benchmark engine '$ENGINE' (expected swift or rust)" >&2
    exit 1
    ;;
esac

"$RUNNER" "$@"
