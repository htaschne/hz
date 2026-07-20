# hz Research Papers

This directory contains research manuscripts and reproducibility artifacts for hz.

| Phase | Paper | Question | Status | Artifacts |
|---:|---|---|---|---|
| 1 | [Recursive Huffman Compression](recursive-huffman/) | What happens when Huffman compression is recursively applied to its own archive output? | Draft project manuscript | Committed CSV snapshots, generated tables, generated PGFPlots data |
| 2 | [Implementation Benchmarks](implementation-benchmarks/) | What engineering trade-offs appear across Swift in-memory, Rust in-memory, and Rust streaming implementations? | Draft scaffold with reproducibility tooling | Deterministic workload generator, smoke/full reproduction script, generated local CSVs, generated tables and figures |

Phase 1 studies recursive/adaptive Huffman behavior. It focuses on archive layering, adaptive stopping, recursive decompression, and deterministic recursive-compression workloads.

Phase 2 studies implementation and memory-model trade-offs across the execution modes currently present in the repository. It may cite Phase 1 for recursive-compression background and reuse workload ideas, but its primary comparisons keep compression mode explicit so single-layer and recursive results are not conflated.

The repository does not currently provide evidence that either paper is peer reviewed.

## Artifact Policy

Tracked artifacts should be small, reviewable, and necessary to build or understand a manuscript:

- LaTeX source;
- bibliography;
- build scripts;
- reproduction scripts;
- small committed CSV snapshots when a paper intentionally depends on them;
- generated aggregate table/figure fragments when needed for reproducible builds.

Ignored artifacts should remain local unless intentionally promoted:

- large generated datasets;
- raw benchmark logs;
- temporary archives;
- LaTeX auxiliary files;
- local environment captures;
- large intermediate CSVs.
