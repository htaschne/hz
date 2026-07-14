#!/usr/bin/env python3
import csv
import pathlib
import sys


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent
    csv_dir = root / "results" / "csv"
    pass_files = sorted(csv_dir.glob("passes-*.csv"))
    if not pass_files:
        print("No pass CSV files found. Run benchmarks/run.sh first.", file=sys.stderr)
        return 1

    for path in pass_files:
        print(f"\n{path.name}")
        with path.open(newline="") as handle:
            rows = list(csv.DictReader(handle))

        by_workload = {}
        for row in rows:
            by_workload.setdefault(row["workload"], []).append(row)

        for workload, workload_rows in sorted(by_workload.items()):
            best = min(workload_rows, key=lambda row: int(row["output_bytes"]))
            first = workload_rows[0]
            accepted_rows = [row for row in workload_rows if row["accepted"] == "true"]
            final = accepted_rows[-1]
            improved = int(best["output_bytes"]) < int(first["output_bytes"])
            print(
                f"- {workload}: best pass {best['pass']} ({best['output_bytes']} bytes), "
                f"first pass {first['output_bytes']} bytes, final {final['output_bytes']} bytes, "
                f"recursive_improved={improved}, verified={final['verified']}"
            )

            previous = None
            for row in workload_rows:
                output = int(row["output_bytes"])
                delta = 0 if previous is None else output - previous
                print(
                    f"  pass {row['pass']}: input={row['input_bytes']} output={output} "
                    f"ratio={row['ratio']} accepted={row['accepted']} delta={delta}"
                )
                previous = output

            print(
                f"  compression_seconds={final['compression_seconds']} "
                f"decompression_seconds={final['decompression_seconds']} "
                f"stopping_reason={final['stopping_reason']}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
