#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAPER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PAPER_DIR/../.." && pwd)"
SMOKE=0

for argument in "$@"; do
  case "$argument" in
    --smoke)
      SMOKE=1
      ;;
    --help|-h)
      cat <<'USAGE'
Usage:
  papers/implementation-benchmarks/artifacts/reproduce.sh [--smoke]

Generates deterministic workloads, runs swift/rust/rust-stream single-layer
benchmarks, verifies decompression through the benchmark runner, captures
environment metadata, and writes normalized CSV plus paper-ready TeX fragments.
USAGE
      exit 0
      ;;
    *)
      echo "error: unsupported argument '$argument'" >&2
      exit 2
      ;;
  esac
done

mkdir -p \
  "$SCRIPT_DIR/workloads" \
  "$SCRIPT_DIR/raw" \
  "$SCRIPT_DIR/results" \
  "$SCRIPT_DIR/logs" \
  "$SCRIPT_DIR/environment" \
  "$PAPER_DIR/figures" \
  "$PAPER_DIR/tables"

GENERATOR_ARGS=("--output-dir" "$SCRIPT_DIR/workloads")
RUNNER_ARGS=("--repo-root" "$REPO_ROOT" "--paper-dir" "$PAPER_DIR" "--workload-dir" "$SCRIPT_DIR/workloads")

if [[ "$SMOKE" -eq 1 ]]; then
  GENERATOR_ARGS+=("--smoke")
  RUNNER_ARGS+=("--smoke")
fi

python3 "$PAPER_DIR/scripts/generate_workloads.py" "${GENERATOR_ARGS[@]}"
python3 "$PAPER_DIR/scripts/run_benchmarks.py" "${RUNNER_ARGS[@]}"

echo "Wrote $SCRIPT_DIR/results/normalized.csv"
echo "Wrote $SCRIPT_DIR/environment/environment.csv"
echo "Wrote $PAPER_DIR/tables"
echo "Wrote $PAPER_DIR/figures"
