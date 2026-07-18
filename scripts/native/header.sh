#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HEADER="$REPO_ROOT/native/hz-native/include/hz_native.h"

if [[ ! -f "$HEADER" ]]; then
  echo "error: missing $HEADER" >&2
  exit 1
fi

echo "Validated manually maintained C ABI header: $HEADER"
echo "No generator is required. Keep Rust #[repr(C)] definitions and this header in sync."
