# Hz Benchmarks

This directory contains a repeatable command-line benchmark runner for the Swift reference engine.

The runner compiles the production engine source files with `swiftc -O`; it does not contain a second Huffman implementation.

## Commands

Baseline single-pass Huffman compression:

```bash
benchmarks/run.sh --max-depth 0
```

Adaptive recursive compression:

```bash
benchmarks/run.sh --adaptive
```

Forced recursive compression to a specific maximum additional depth:

```bash
benchmarks/run.sh --max-depth 3
```

Benchmark one file:

```bash
benchmarks/run.sh --input Mocks/bible.txt --max-depth 0
```

Analyze generated pass CSV files:

```bash
benchmarks/analyze.py
```

## Workloads

When no `--input` or `--workloads` path is supplied, the runner creates deterministic workloads under `benchmarks/workloads/generated/`:

- repetitive text
- prose-like text
- random high-entropy binary data
- repeated single-byte data
- compressed-like deterministic binary data

## Results

CSV files are written to `benchmarks/results/csv/`.
Archive outputs are written to `benchmarks/results/raw/`.

Generated results are ignored by git.

Important CSV fields include:

- `workload`
- `mode`
- `configured_max_depth`
- `pass`
- `input_bytes`
- `output_bytes`
- `ratio`
- `accepted`
- `best_pass`
- `accepted_layer_count`
- `stopping_reason`
- `compression_seconds`
- `decompression_seconds`
- `verified`

