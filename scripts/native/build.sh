#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CRATE_DIR="$REPO_ROOT/native/hz-native"
TARGET="${HZ_NATIVE_TARGET:-aarch64-apple-darwin}"
CONFIGURATION="${1:-Debug}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: Cargo is required to build hz-native. Install Rust from https://rustup.rs/." >&2
  exit 127
fi

case "$CONFIGURATION" in
  Release|release)
    PROFILE_FLAG=(--release)
    ;;
  *)
    PROFILE_FLAG=()
    ;;
esac

cargo build \
  --manifest-path "$CRATE_DIR/Cargo.toml" \
  --target "$TARGET" \
  "${PROFILE_FLAG[@]}"
