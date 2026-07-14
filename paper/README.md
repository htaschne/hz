# Recursive Huffman Paper

This directory contains an IEEE two-column conference-style paper about the recursive Huffman implementation and benchmark suite.

Build the paper:

```sh
make -C paper
```

Regenerate benchmark artifacts after running the benchmark suite:

```sh
cp benchmarks/results/csv/summary-adaptive-*.csv paper/data/summary-adaptive.csv
cp benchmarks/results/csv/summary-baseline-*.csv paper/data/summary-baseline.csv
cp benchmarks/results/csv/passes-adaptive-*.csv paper/data/passes-adaptive.csv
make -C paper artifacts
```

The committed CSV snapshots are benchmark outputs produced by the repository's benchmark runner. The paper does not rely on external or manually invented measurements.
