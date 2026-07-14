#!/usr/bin/env python3
"""Generate LaTeX tables and PGFPlots data from benchmark CSV snapshots."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


WORKLOAD_LABELS = {
    "compressed-like": "Compressed-like",
    "high-entropy": "High entropy",
    "ordinary-prose": "Ordinary prose",
    "repetitive-text": "Repetitive text",
    "single-byte": "Single byte",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def format_int(value: str | int) -> str:
    return f"{int(value):,}"


def format_ratio(output_bytes: str | int, original_bytes: str | int) -> str:
    ratio = int(output_bytes) / int(original_bytes)
    return f"{ratio:.3f}"


def format_percent_delta(output_bytes: str | int, original_bytes: str | int) -> str:
    delta = (int(output_bytes) / int(original_bytes) - 1.0) * 100.0
    return f"{delta:+.1f}\\%"


def escape_latex(text: str) -> str:
    return text.replace("_", "\\_")


def generate_summary_table(adaptive: list[dict[str, str]], baseline: list[dict[str, str]]) -> str:
    baseline_by_workload = {row["workload"]: row for row in baseline}
    rows = []
    for row in adaptive:
        base = baseline_by_workload[row["workload"]]
        rows.append(
            " & ".join(
                [
                    WORKLOAD_LABELS[row["workload"]],
                    format_int(row["original_bytes"]),
                    format_int(base["final_archive_bytes"]),
                    format_int(row["final_archive_bytes"]),
                    row["accepted_layer_count"],
                    format_ratio(row["final_archive_bytes"], row["original_bytes"]),
                    format_percent_delta(row["final_archive_bytes"], row["original_bytes"]),
                ]
            )
            + r" \\"
        )

    return "\n".join(
        [
            r"\begin{table}[t]",
            r"\caption{Adaptive recursive Huffman results. ``Baseline'' is one Huffman archive layer.}",
            r"\label{tab:results}",
            r"\centering",
            r"\scriptsize",
            r"\begin{tabular*}{\columnwidth}{@{\extracolsep{\fill}}lrrrrrr@{}}",
            r"\toprule",
            r"Workload & In & 1-pass & Adapt. & L & Ratio & $\Delta$ \\",
            r"\midrule",
            *rows,
            r"\bottomrule",
            r"\end{tabular*}",
            r"\end{table}",
            "",
        ]
    )


def generate_pass_table(passes: list[dict[str, str]]) -> str:
    rows = []
    for row in passes:
        rows.append(
            " & ".join(
                [
                    WORKLOAD_LABELS[row["workload"]],
                    row["pass"],
                    format_int(row["input_bytes"]),
                    format_int(row["output_bytes"]),
                    f"{float(row['ratio']):.3f}",
                    "yes" if row["accepted"] == "true" else "no",
                ]
            )
            + r" \\"
        )

    return "\n".join(
        [
            r"\begin{table}[t]",
            r"\caption{Compression trajectory for adaptive mode. Rejected rows are attempted layers that were discarded by the stopping rule.}",
            r"\label{tab:passes}",
            r"\centering",
            r"\small",
            r"\begin{tabular}{lrrrrr}",
            r"\toprule",
            r"Workload & Pass & Input & Output & Ratio & Accepted \\",
            r"\midrule",
            *rows,
            r"\bottomrule",
            r"\end{tabular}",
            r"\end{table}",
            "",
        ]
    )


def generate_trajectory_data(passes: list[dict[str, str]]) -> str:
    lines = ["workload pass output_bytes accepted"]
    for row in passes:
        label = row["workload"].replace("-", "_")
        lines.append(f"{label} {row['pass']} {row['output_bytes']} {1 if row['accepted'] == 'true' else 0}")
    return "\n".join(lines) + "\n"


def generate_trajectory_plot(passes: list[dict[str, str]]) -> str:
    rows_by_workload: dict[str, list[dict[str, str]]] = {}
    for row in passes:
        rows_by_workload.setdefault(row["workload"], []).append(row)

    plots = []
    for workload, rows in rows_by_workload.items():
        coordinates = " ".join(f"({row['pass']},{row['output_bytes']})" for row in rows)
        plots.extend(
            [
                rf"\addplot+[mark=*] coordinates {{{coordinates}}};",
                rf"\addlegendentry{{{WORKLOAD_LABELS[workload]}}}",
            ]
        )

    return "\n".join(
        [
            r"\begin{tikzpicture}",
            r"\begin{axis}[",
            r"    width=\columnwidth,",
            r"    height=5.4cm,",
            r"    xlabel={Pass},",
            r"    ylabel={Output bytes},",
            r"    ymode=log,",
            r"    grid=both,",
            r"    legend style={font=\scriptsize, at={(0.5,-0.27)}, anchor=north, legend columns=2},",
            r"    tick label style={font=\scriptsize},",
            r"    label style={font=\scriptsize}",
            r"]",
            *plots,
            r"\end{axis}",
            r"\end{tikzpicture}",
            "",
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--output-dir", type=Path, default=Path("generated"))
    args = parser.parse_args()

    adaptive = read_csv(args.data_dir / "summary-adaptive.csv")
    baseline = read_csv(args.data_dir / "summary-baseline.csv")
    passes = read_csv(args.data_dir / "passes-adaptive.csv")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "results-table.tex").write_text(
        generate_summary_table(adaptive, baseline),
        encoding="utf-8",
    )
    (args.output_dir / "passes-table.tex").write_text(
        generate_pass_table(passes),
        encoding="utf-8",
    )
    (args.output_dir / "trajectory.dat").write_text(
        generate_trajectory_data(passes),
        encoding="utf-8",
    )
    (args.output_dir / "trajectory-plot.tex").write_text(
        generate_trajectory_plot(passes),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
