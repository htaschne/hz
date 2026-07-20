#!/usr/bin/env python3
"""Generate deterministic benchmark workloads for the implementation paper."""

from __future__ import annotations

import argparse
import csv
import math
import random
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class WorkloadSpec:
    name: str
    distribution: str
    size: int
    seed: int
    alphabet_size: int | None
    description: str


SMOKE_SPECS = [
    WorkloadSpec("single-4k", "single", 4096, 0x1001, 1, "one repeated byte"),
    WorkloadSpec("prose-4k", "ordinary-prose", 4096, 0x1002, None, "deterministic prose text"),
    WorkloadSpec("random-4k", "random", 4096, 0x1003, 256, "high-entropy pseudorandom bytes"),
]


FULL_SPECS = [
    WorkloadSpec("single-64k", "single", 64 * 1024, 0x2001, 1, "one repeated byte"),
    WorkloadSpec("binary-balanced-64k", "binary-balanced", 64 * 1024, 0x2002, 2, "two symbols with equal probability"),
    WorkloadSpec("binary-skewed-64k", "binary-skewed", 64 * 1024, 0x2003, 2, "two symbols with a 90/10 split"),
    WorkloadSpec("uniform-4-64k", "uniform-k", 64 * 1024, 0x2004, 4, "uniform small alphabet"),
    WorkloadSpec("uniform-16-64k", "uniform-k", 64 * 1024, 0x2005, 16, "uniform medium alphabet"),
    WorkloadSpec("uniform-256-64k", "uniform-256", 64 * 1024, 0x2006, 256, "uniform full byte alphabet"),
    WorkloadSpec("zipf-64k", "zipf", 64 * 1024, 0x2007, 32, "Zipf-like categorical distribution"),
    WorkloadSpec("markov-64k", "markov", 64 * 1024, 0x2008, 8, "Markov-correlated byte sequence"),
    WorkloadSpec("ordinary-prose-64k", "ordinary-prose", 64 * 1024, 0x2009, None, "deterministic prose text"),
    WorkloadSpec("source-code-64k", "source-code", 64 * 1024, 0x2010, None, "source-code-like text"),
    WorkloadSpec("random-64k", "random", 64 * 1024, 0x2011, 256, "high-entropy pseudorandom bytes"),
    WorkloadSpec("compressed-like-64k", "compressed-like", 64 * 1024, 0x2012, 256, "deterministic compressed-like bytes"),
    WorkloadSpec("recursive-repetitive-64k", "recursive-repetitive", 64 * 1024, 0x2013, None, "repetitive workload similar to recursive paper inputs"),
    WorkloadSpec("prose-1m", "ordinary-prose", 1024 * 1024, 0x2014, None, "larger deterministic prose text"),
    WorkloadSpec("random-1m", "random", 1024 * 1024, 0x2015, 256, "larger high-entropy pseudorandom bytes"),
]


PROSE = (
    "Huffman coding assigns shorter bit patterns to symbols that appear more often. "
    "This workload is deterministic prose with punctuation, spaces, and repeated words. "
)

SOURCE = (
    "struct BenchmarkCase { let name: String; let bytes: [UInt8] }\n"
    "func run(case input: BenchmarkCase) throws { try engine.compress(Data(input.bytes)) }\n"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    specs = SMOKE_SPECS if args.smoke else FULL_SPECS
    rows = []

    for spec in specs:
        data = generate(spec)
        path = args.output_dir / f"{spec.name}.bin"
        path.write_bytes(data)
        rows.append(
            {
                "workload": spec.name,
                "distribution": spec.distribution,
                "seed": spec.seed,
                "input_size": len(data),
                "alphabet_size": "" if spec.alphabet_size is None else spec.alphabet_size,
                "empirical_entropy_bits_per_byte": f"{empirical_entropy(data):.6f}",
                "path": path.name,
                "description": spec.description,
            }
        )

    with (args.output_dir / "manifest.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def generate(spec: WorkloadSpec) -> bytes:
    rng = random.Random(spec.seed)
    if spec.distribution == "single":
        return bytes([0x41]) * spec.size
    if spec.distribution == "binary-balanced":
        return bytes(0x41 if rng.random() < 0.5 else 0x42 for _ in range(spec.size))
    if spec.distribution == "binary-skewed":
        return bytes(0x41 if rng.random() < 0.9 else 0x42 for _ in range(spec.size))
    if spec.distribution == "uniform-k":
        alphabet = list(range(spec.alphabet_size or 4))
        return bytes(rng.choice(alphabet) for _ in range(spec.size))
    if spec.distribution == "uniform-256":
        return bytes(rng.randrange(256) for _ in range(spec.size))
    if spec.distribution == "zipf":
        return zipf_bytes(rng, spec.size, spec.alphabet_size or 32)
    if spec.distribution == "markov":
        return markov_bytes(rng, spec.size, spec.alphabet_size or 8)
    if spec.distribution == "ordinary-prose":
        return repeated_text(PROSE, spec.size)
    if spec.distribution == "source-code":
        return repeated_text(SOURCE, spec.size)
    if spec.distribution == "random":
        return bytes(rng.randrange(256) for _ in range(spec.size))
    if spec.distribution == "compressed-like":
        return compressed_like_bytes(spec.size, spec.seed)
    if spec.distribution == "recursive-repetitive":
        return repeated_text("aaaaabbbbbcccccdddddeeeee\n", spec.size)
    raise ValueError(f"unsupported distribution: {spec.distribution}")


def zipf_bytes(rng: random.Random, size: int, alphabet_size: int) -> bytes:
    weights = [1.0 / (rank + 1) for rank in range(alphabet_size)]
    total = sum(weights)
    cumulative = []
    running = 0.0
    for weight in weights:
        running += weight / total
        cumulative.append(running)

    output = bytearray()
    for _ in range(size):
        sample = rng.random()
        for index, threshold in enumerate(cumulative):
            if sample <= threshold:
                output.append(index)
                break
    return bytes(output)


def markov_bytes(rng: random.Random, size: int, alphabet_size: int) -> bytes:
    current = rng.randrange(alphabet_size)
    output = bytearray()
    for _ in range(size):
        if rng.random() < 0.85:
            current = current
        else:
            current = rng.randrange(alphabet_size)
        output.append(current)
    return bytes(output)


def compressed_like_bytes(size: int, seed: int) -> bytes:
    state = seed & 0xFFFFFFFFFFFFFFFF
    output = bytearray()
    while len(output) < size:
        state = (state * 2862933555777941757 + 3037000493) & 0xFFFFFFFFFFFFFFFF
        output.append((state >> 40) & 0xFF)
        if len(output) % 31 == 0 and len(output) < size:
            output.append(0)
    return bytes(output[:size])


def repeated_text(text: str, size: int) -> bytes:
    encoded = text.encode("utf-8")
    repeats = (size // len(encoded)) + 1
    return (encoded * repeats)[:size]


def empirical_entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = [0] * 256
    for byte in data:
        counts[byte] += 1
    total = len(data)
    entropy = 0.0
    for count in counts:
        if count:
            probability = count / total
            entropy -= probability * math.log2(probability)
    return entropy


if __name__ == "__main__":
    main()
