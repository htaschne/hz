#!/usr/bin/env python3
"""Run hz benchmark modes and generate paper-ready CSV, tables, and figures."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import platform
import re
import subprocess
import sys
from pathlib import Path


ENGINES = ["swift", "rust", "rust-stream"]
RESULT_FIELDS = [
    "workload",
    "distribution",
    "seed",
    "input_size",
    "empirical_entropy_bits_per_byte",
    "engine",
    "compression_mode",
    "requested_max_depth",
    "accepted_recursive_layers",
    "original_size",
    "archive_size",
    "compression_ratio",
    "compression_seconds",
    "decompression_seconds",
    "compression_throughput_bytes_per_second",
    "decompression_throughput_bytes_per_second",
    "peak_rss_bytes",
    "exit_status",
    "verified",
    "benchmark_output_dir",
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--paper-dir", type=Path, required=True)
    parser.add_argument("--workload-dir", type=Path, required=True)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    paper_dir = args.paper_dir.resolve()
    manifest = read_csv(args.workload_dir / "manifest.csv")

    raw_dir = paper_dir / "artifacts" / "raw"
    results_dir = paper_dir / "artifacts" / "results"
    logs_dir = paper_dir / "artifacts" / "logs"
    env_dir = paper_dir / "artifacts" / "environment"
    figures_dir = paper_dir / "figures"
    tables_dir = paper_dir / "tables"
    for directory in [raw_dir, results_dir, logs_dir, env_dir, figures_dir, tables_dir]:
        directory.mkdir(parents=True, exist_ok=True)

    rows = []
    for workload in manifest:
        input_path = args.workload_dir / workload["path"]
        for engine in ENGINES:
            rows.append(run_one(repo_root, raw_dir, logs_dir, workload, input_path, engine))

    write_csv(results_dir / "normalized.csv", RESULT_FIELDS, rows)
    environment = capture_environment(repo_root, args.smoke)
    write_environment(env_dir / "environment.csv", environment)
    generate_tables(tables_dir, manifest, rows, environment)
    generate_figures(figures_dir, rows)


def run_one(
    repo_root: Path,
    raw_dir: Path,
    logs_dir: Path,
    workload: dict[str, str],
    input_path: Path,
    engine: str,
) -> dict[str, str]:
    output_dir = raw_dir / engine / workload["workload"]
    output_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / f"{engine}-{workload['workload']}.log"
    command = [
        str(repo_root / "benchmarks" / "run.sh"),
        "--engine",
        engine,
        "--max-depth",
        "0",
        "--input",
        str(input_path),
        "--output",
        str(output_dir),
    ]
    timed_command = ["/usr/bin/time", "-l", *command] if Path("/usr/bin/time").exists() else command
    completed = subprocess.run(
        timed_command,
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    log_path.write_text(
        "$ " + " ".join(command) + "\n\nSTDOUT\n" + completed.stdout + "\nSTDERR\n" + completed.stderr,
        encoding="utf-8",
    )
    peak_rss = parse_peak_rss(completed.stderr)

    if completed.returncode != 0:
        return failure_row(workload, engine, output_dir, completed.returncode, peak_rss)

    summary_files = sorted((output_dir / "csv").glob("summary-*.csv"))
    if not summary_files:
        return failure_row(workload, engine, output_dir, 1, peak_rss)

    summary = read_csv(summary_files[-1])[0]
    original_size = int(summary["original_bytes"])
    archive_size = int(summary["final_archive_bytes"])
    compression_seconds = float(summary["compression_seconds"])
    decompression_seconds = float(summary["decompression_seconds"])

    return {
        "workload": workload["workload"],
        "distribution": workload["distribution"],
        "seed": workload["seed"],
        "input_size": workload["input_size"],
        "empirical_entropy_bits_per_byte": workload["empirical_entropy_bits_per_byte"],
        "engine": engine,
        "compression_mode": "single-layer",
        "requested_max_depth": "0",
        "accepted_recursive_layers": summary["accepted_layer_count"],
        "original_size": str(original_size),
        "archive_size": str(archive_size),
        "compression_ratio": f"{archive_size / original_size if original_size else 0:.9f}",
        "compression_seconds": f"{compression_seconds:.9f}",
        "decompression_seconds": f"{decompression_seconds:.9f}",
        "compression_throughput_bytes_per_second": f"{throughput(original_size, compression_seconds):.3f}",
        "decompression_throughput_bytes_per_second": f"{throughput(original_size, decompression_seconds):.3f}",
        "peak_rss_bytes": "" if peak_rss is None else str(peak_rss),
        "exit_status": str(completed.returncode),
        "verified": summary["verified"],
        "benchmark_output_dir": str(output_dir.relative_to(repo_root)),
    }


def failure_row(
    workload: dict[str, str],
    engine: str,
    output_dir: Path,
    exit_status: int,
    peak_rss: int | None,
) -> dict[str, str]:
    row = {field: "" for field in RESULT_FIELDS}
    row.update(
        {
            "workload": workload["workload"],
            "distribution": workload["distribution"],
            "seed": workload["seed"],
            "input_size": workload["input_size"],
            "empirical_entropy_bits_per_byte": workload["empirical_entropy_bits_per_byte"],
            "engine": engine,
            "compression_mode": "single-layer",
            "requested_max_depth": "0",
            "peak_rss_bytes": "" if peak_rss is None else str(peak_rss),
            "exit_status": str(exit_status),
            "verified": "false",
            "benchmark_output_dir": str(output_dir),
        }
    )
    return row


def throughput(byte_count: int, seconds: float) -> float:
    if seconds <= 0:
        return 0.0
    return byte_count / seconds


def parse_peak_rss(stderr: str) -> int | None:
    for line in stderr.splitlines():
        match = re.search(r"(\d+)\s+maximum resident set size", line)
        if match:
            return int(match.group(1))
    return None


def capture_environment(repo_root: Path, smoke: bool) -> list[tuple[str, str]]:
    command = "./artifacts/reproduce.sh --smoke" if smoke else "./artifacts/reproduce.sh"
    status = run_text(["git", "status", "--short"], repo_root)
    return [
        ("benchmark_date_utc", dt.datetime.now(dt.timezone.utc).isoformat()),
        ("git_commit", run_text(["git", "rev-parse", "HEAD"], repo_root)),
        ("git_status", "dirty" if status else "clean"),
        ("operating_system", platform.platform()),
        ("architecture", platform.machine()),
        ("cpu_model", sysctl("machdep.cpu.brand_string")),
        ("logical_cpu_count", str(os.cpu_count() or "")),
        ("memory_bytes", sysctl("hw.memsize")),
        ("swift_version", first_line(run_text(["swift", "--version"], repo_root))),
        ("rust_version", run_text(["rustc", "--version"], repo_root)),
        ("compiler_build_mode", "benchmarks/run.sh uses swiftc -O and Rust Release for native modes"),
        ("benchmark_command", command),
        ("peak_rss_method", "/usr/bin/time -l maximum resident set size, bytes, when available"),
    ]


def sysctl(name: str) -> str:
    try:
        return subprocess.check_output(["sysctl", "-n", name], text=True).strip()
    except Exception:
        return ""


def run_text(command: list[str], cwd: Path) -> str:
    try:
        return subprocess.check_output(command, cwd=cwd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def first_line(text: str) -> str:
    return text.splitlines()[0] if text else ""


def generate_tables(
    tables_dir: Path,
    manifest: list[dict[str, str]],
    rows: list[dict[str, str]],
    environment: list[tuple[str, str]],
) -> None:
    (tables_dir / "implementation-summary.tex").write_text(implementation_summary_table(), encoding="utf-8")
    (tables_dir / "workload-definitions.tex").write_text(workload_table(manifest), encoding="utf-8")
    (tables_dir / "environment.tex").write_text(environment_table(environment), encoding="utf-8")
    (tables_dir / "primary-results.tex").write_text(primary_results_table(rows), encoding="utf-8")


def implementation_summary_table() -> str:
    return "\n".join(
        [
            r"\begin{table}[t]",
            r"\caption{Implementations under study.}",
            r"\label{tab:implementation-summary}",
            r"\centering",
            r"\small",
            r"\begin{tabular}{llll}",
            r"\toprule",
            r"Mode & Language & Memory model & Boundary \\",
            r"\midrule",
            r"Swift & Swift & In-memory \texttt{Data} & none \\",
            r"Rust & Rust & In-memory buffers & C ABI \\",
            r"Rust streaming & Rust & Bounded file I/O & C ABI paths \\",
            r"\bottomrule",
            r"\end{tabular}",
            r"\end{table}",
            "",
        ]
    )


def workload_table(manifest: list[dict[str, str]]) -> str:
    body = []
    for row in manifest:
        body.append(
            " & ".join(
                [
                    tex(row["workload"]),
                    tex(row["distribution"]),
                    format_int(row["input_size"]),
                    row["empirical_entropy_bits_per_byte"],
                ]
            )
            + r" \\"
        )
    return "\n".join(
        [
            r"\begin{table}[t]",
            r"\caption{Generated workload definitions. Entropy is empirical byte entropy in bits per byte.}",
            r"\label{tab:workloads}",
            r"\centering",
            r"\scriptsize",
            r"\begin{tabular}{llrr}",
            r"\toprule",
            r"Workload & Distribution & Bytes & Entropy \\",
            r"\midrule",
            *body,
            r"\bottomrule",
            r"\end{tabular}",
            r"\end{table}",
            "",
        ]
    )


def environment_table(environment: list[tuple[str, str]]) -> str:
    rows = [f"{tex(key)} & {tex(value)} \\\\" for key, value in environment]
    return "\n".join(
        [
            r"\begin{table}[t]",
            r"\caption{Benchmark environment captured at reproduction time.}",
            r"\label{tab:environment}",
            r"\centering",
            r"\scriptsize",
            r"\begin{tabular}{ll}",
            r"\toprule",
            r"Field & Value \\",
            r"\midrule",
            *rows,
            r"\bottomrule",
            r"\end{tabular}",
            r"\end{table}",
            "",
        ]
    )


def primary_results_table(rows: list[dict[str, str]]) -> str:
    body = []
    for row in rows:
        body.append(
            " & ".join(
                [
                    tex(row["workload"]),
                    tex(row["engine"]),
                    format_int(row["archive_size"]),
                    f"{float(row['compression_ratio']):.3f}" if row["compression_ratio"] else "--",
                    mib_per_second(row["compression_throughput_bytes_per_second"]),
                    mib_per_second(row["decompression_throughput_bytes_per_second"]),
                    format_rss(row["peak_rss_bytes"]),
                    tex(row["verified"]),
                ]
            )
            + r" \\"
        )
    return "\n".join(
        [
            r"\begin{table*}[t]",
            r"\caption{Primary single-layer benchmark results. Throughput is MiB/s; peak RSS is captured by \texttt{/usr/bin/time -l} when available.}",
            r"\label{tab:primary-results}",
            r"\centering",
            r"\scriptsize",
            r"\begin{tabular}{llrrrrrl}",
            r"\toprule",
            r"Workload & Engine & Archive & Ratio & Comp. & Decomp. & RSS & Verified \\",
            r"\midrule",
            *body,
            r"\bottomrule",
            r"\end{tabular}",
            r"\end{table*}",
            "",
        ]
    )


def generate_figures(figures_dir: Path, rows: list[dict[str, str]]) -> None:
    write_bar_figure(
        figures_dir / "compression-throughput.tex",
        rows,
        "compression_throughput_bytes_per_second",
        "Compression throughput (MiB/s)",
    )
    write_bar_figure(
        figures_dir / "decompression-throughput.tex",
        rows,
        "decompression_throughput_bytes_per_second",
        "Decompression throughput (MiB/s)",
    )
    write_scatter(
        figures_dir / "ratio-vs-entropy.tex",
        rows,
        "empirical_entropy_bits_per_byte",
        "compression_ratio",
        "Empirical byte entropy",
        "Archive ratio",
    )
    write_scatter(
        figures_dir / "peak-rss-vs-input-size.tex",
        [row for row in rows if row["peak_rss_bytes"]],
        "input_size",
        "peak_rss_bytes",
        "Input bytes",
        "Peak RSS bytes",
    )
    write_stream_overhead(figures_dir / "rust-stream-overhead.tex", rows)


def write_bar_figure(path: Path, rows: list[dict[str, str]], field: str, ylabel: str) -> None:
    labels = [f"{row['engine']}:{row['workload']}" for row in rows]
    coords = []
    for index, row in enumerate(rows, start=1):
        value = float(row[field]) / (1024 * 1024) if row[field] else 0.0
        coords.append(f"({index},{value:.3f})")
    path.write_text(
        "\n".join(
            [
                r"\begin{tikzpicture}",
                r"\begin{axis}[",
                r"    width=\columnwidth,",
                r"    height=5.2cm,",
                r"    ybar,",
                rf"    ylabel={{{ylabel}}},",
                rf"    xtick={{{','.join(str(i) for i in range(1, len(labels) + 1))}}},",
                rf"    xticklabels={{{','.join(tex(label) for label in labels)}}},",
                r"    x tick label style={rotate=60, anchor=east, font=\tiny},",
                r"    tick label style={font=\scriptsize},",
                r"    label style={font=\scriptsize},",
                r"    grid=major",
                r"]",
                rf"\addplot coordinates {{{' '.join(coords)}}};",
                r"\end{axis}",
                r"\end{tikzpicture}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def write_scatter(path: Path, rows: list[dict[str, str]], x_field: str, y_field: str, xlabel: str, ylabel: str) -> None:
    plots = []
    for engine in ENGINES:
        coords = []
        for row in rows:
            if row["engine"] == engine and row[x_field] and row[y_field]:
                coords.append(f"({float(row[x_field]):.6f},{float(row[y_field]):.6f})")
        plots.append(rf"\addplot+[only marks] coordinates {{{' '.join(coords)}}};")
        plots.append(rf"\addlegendentry{{{tex(engine)}}}")
    path.write_text(
        "\n".join(
            [
                r"\begin{tikzpicture}",
                r"\begin{axis}[",
                r"    width=\columnwidth,",
                r"    height=5.2cm,",
                rf"    xlabel={{{xlabel}}},",
                rf"    ylabel={{{ylabel}}},",
                r"    legend style={font=\scriptsize},",
                r"    tick label style={font=\scriptsize},",
                r"    label style={font=\scriptsize},",
                r"    grid=major",
                r"]",
                *plots,
                r"\end{axis}",
                r"\end{tikzpicture}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def write_stream_overhead(path: Path, rows: list[dict[str, str]]) -> None:
    by_key = {(row["workload"], row["engine"]): row for row in rows}
    coords = []
    labels = []
    for workload in sorted({row["workload"] for row in rows}):
        rust = by_key.get((workload, "rust"))
        stream = by_key.get((workload, "rust-stream"))
        if not rust or not stream or not rust["compression_seconds"] or not stream["compression_seconds"]:
            continue
        base = float(rust["compression_seconds"])
        value = ((float(stream["compression_seconds"]) / base) - 1.0) * 100.0 if base else 0.0
        labels.append(workload)
        coords.append(f"({len(labels)},{value:.3f})")
    path.write_text(
        "\n".join(
            [
                r"\begin{tikzpicture}",
                r"\begin{axis}[",
                r"    width=\columnwidth,",
                r"    height=5.2cm,",
                r"    ybar,",
                r"    ylabel={Rust streaming compression time delta (\%)},",
                rf"    xtick={{{','.join(str(i) for i in range(1, len(labels) + 1))}}},",
                rf"    xticklabels={{{','.join(tex(label) for label in labels)}}},",
                r"    x tick label style={rotate=45, anchor=east, font=\tiny},",
                r"    tick label style={font=\scriptsize},",
                r"    label style={font=\scriptsize},",
                r"    grid=major",
                r"]",
                rf"\addplot coordinates {{{' '.join(coords)}}};",
                r"\end{axis}",
                r"\end{tikzpicture}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_environment(path: Path, environment: list[tuple[str, str]]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["field", "value"])
        writer.writerows(environment)


def tex(value: object) -> str:
    text = str(value)
    replacements = {
        "\\": r"\textbackslash{}",
        "_": r"\_",
        "%": r"\%",
        "&": r"\&",
        "#": r"\#",
        "$": r"\$",
        "{": r"\{",
        "}": r"\}",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    return text


def format_int(value: str) -> str:
    return f"{int(value):,}" if value else "--"


def mib_per_second(value: str) -> str:
    return f"{float(value) / (1024 * 1024):.2f}" if value else "--"


def format_rss(value: str) -> str:
    if not value:
        return "--"
    return f"{int(value) / (1024 * 1024):.1f}"


if __name__ == "__main__":
    main()
