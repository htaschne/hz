# Implementation Benchmarks

Paper: **Engineering Trade-offs in Huffman Compression: An Experimental Comparison of Swift, Rust, and Streaming Implementations**

## Research Objective

This paper studies implementation-level trade-offs among the execution modes currently present in hz:

- Swift in-memory compression and decompression;
- Rust in-memory compression and decompression through the Swift C ABI bridge;
- Rust bounded-memory file streaming.

The goal is not a broad Swift-versus-Rust language comparison. The study keeps the `.hz` archive format and single-layer compression mode fixed, then measures throughput, archive ratio, decompression performance, peak RSS, input-size scaling, byte distributions, and integration overhead where observable.

## Status

Draft scaffold with reproducibility tooling. Result claims should be added only after a full benchmark campaign has produced verified data.

## Build The Manuscript

```sh
make -C papers/implementation-benchmarks
```

The paper compiles before benchmark results exist. Missing generated result fragments are replaced with explicit placeholders.

## Reproduce Benchmarks

Smoke run:

```sh
papers/implementation-benchmarks/artifacts/reproduce.sh --smoke
```

Full local campaign:

```sh
papers/implementation-benchmarks/artifacts/reproduce.sh
```

The smoke run is intended for local validation and CI-style checks. It generates a small deterministic workload set and runs all three engines. The full campaign generates a broader controlled workload matrix.

## Outputs

Generated outputs are written under this paper directory:

- `artifacts/workloads/`: deterministic input files and workload manifest.
- `artifacts/raw/`: benchmark runner outputs for each engine/workload pair.
- `artifacts/results/normalized.csv`: normalized benchmark matrix.
- `artifacts/environment/environment.csv`: local environment metadata.
- `artifacts/logs/`: command logs and `/usr/bin/time -l` output.
- `tables/`: generated LaTeX table fragments.
- `figures/`: generated PGFPlots figure fragments.

## Committed Artifacts

Tracked:

- manuscript source;
- bibliography;
- build files;
- workload and reproduction scripts;
- directory `.gitkeep` files.

Ignored:

- generated workloads;
- raw archives and benchmark logs;
- normalized local CSV results;
- local environment captures;
- generated table and figure fragments;
- LaTeX auxiliary files and compiled PDFs.

Generated benchmark data may be promoted to tracked paper artifacts later if the repository adopts a reviewed snapshot policy.

## Known Limitations

- Peak RSS is captured with `/usr/bin/time -l` on macOS when available and is process-level.
- Rust in-memory measurements include the Swift benchmark runner and C ABI integration path.
- Rust streaming measurements exercise the path-based file API and temporary destination workflow.
- Recursive/adaptive compression is intentionally separate from the primary single-layer comparison.
- Smoke results are validation artifacts, not final experimental evidence.
