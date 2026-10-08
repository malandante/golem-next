#!/usr/bin/env python3
"""Summarize repeated physical timing reports produced by analyze_uart_capture."""

from __future__ import annotations

import argparse
import glob
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def percentile(values: list[float], percent: float) -> float:
    """Nearest-rank percentile; deterministic and dependency-free."""
    if not values:
        raise ValueError("cannot calculate a percentile of no values")
    ordered = sorted(values)
    rank = max(1, math.ceil(percent / 100.0 * len(ordered)))
    return ordered[rank - 1]


def summarize_report(report: dict[str, object]) -> dict[str, object]:
    timing = report.get("timing")
    if not isinstance(timing, list) or not timing:
        raise ValueError("report contains no timing observations")
    by_event: dict[str, list[float]] = defaultdict(list)
    runs = set()
    for row in timing:
        if not isinstance(row, dict):
            raise ValueError("invalid timing row")
        by_event[str(row["event"])].append(float(row["error_s"]) * 1000.0)
        runs.add(int(row["run"]))

    events = []
    for event, errors in by_event.items():
        median = statistics.median(errors)
        deviations = [abs(value - median) for value in errors]
        events.append(
            {
                "event": event,
                "samples": len(errors),
                "mean_error_ms": statistics.fmean(errors),
                "median_error_ms": median,
                "min_error_ms": min(errors),
                "max_error_ms": max(errors),
                "peak_to_peak_jitter_ms": max(errors) - min(errors),
                "p95_abs_error_ms": percentile([abs(value) for value in errors], 95),
                "p95_jitter_from_median_ms": percentile(deviations, 95),
            }
        )
    return {
        "capture": report.get("capture", ""),
        "runs": len(runs),
        "source_passed": bool(report.get("passed")),
        "worst_abs_error_ms": max(event["p95_abs_error_ms"] for event in events),
        "worst_peak_to_peak_jitter_ms": max(event["peak_to_peak_jitter_ms"] for event in events),
        "events": events,
    }


def markdown(summaries: list[dict[str, object]]) -> str:
    lines = [
        "| Captura | Runs | PASS origen | Peor error abs. p95 (ms) | Peor jitter p-p (ms) |",
        "| --- | ---: | :---: | ---: | ---: |",
    ]
    for summary in summaries:
        lines.append(
            f"| {summary['capture']} | {summary['runs']} | "
            f"{'sí' if summary['source_passed'] else 'no'} | "
            f"{summary['worst_abs_error_ms']:.3f} | "
            f"{summary['worst_peak_to_peak_jitter_ms']:.3f} |"
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", help="JSON paths or wildcard patterns")
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    args = parser.parse_args()

    try:
        paths = []
        for pattern in args.reports:
            matches = sorted(Path(match) for match in glob.glob(pattern))
            paths.extend(matches or [Path(pattern)])
        summaries = [
            summarize_report(json.loads(path.read_text(encoding="utf-8")))
            for path in paths
        ]
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    table = markdown(summaries)
    print(table, end="")
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(summaries, indent=2) + "\n", encoding="utf-8")
    if args.markdown_output:
        args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_output.write_text(table, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
