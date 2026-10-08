#!/usr/bin/env python3
"""Validate decoded UART CSV captures from the physical golem-next link.

The input is deliberately analyzer-neutral.  Logic 2, PulseView or another
decoder may be used as long as the exported CSV contains a timestamp and a
decoded byte.  Column names and units can be selected explicitly when their
automatic detection is not sufficient.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from capture_timing import MARKERS, NOTE_MARKERS, measure_note_durations


TIME_COLUMNS = ("timestamp_seconds", "time [s]", "start time [s]", "time", "timestamp")
VALUE_COLUMNS = ("byte", "data", "value", "decoded data")
DIRECTION_COLUMNS = ("direction", "channel", "analyzer name", "analyzer")
ERROR_WORDS = ("parity error", "framing error", "frame error")
UNIT_SCALE = {"s": 1.0, "ms": 1e-3, "us": 1e-6, "ns": 1e-9}


def all_notes_off() -> bytes:
    """Channel cleanup emitted by .GOLEM (formerly .MT32) since #3: CC64=0, CC123=0, CC120=0."""
    return bytes(
        value
        for channel in range(16)
        for value in (
            0xB0 + channel, 0x40, 0x00,
            0xB0 + channel, 0x7B, 0x00,
            0xB0 + channel, 0x78, 0x00,
        )
    )


def start_cleanup() -> bytes:
    """Sent by .GOLEM play before the song since 2026-10-06: CC64=0, CC123=0,
    CC120=0 and CC7=100 per channel (notes left by a session cut short)."""
    return bytes(
        value
        for channel in range(16)
        for value in (
            0xB0 + channel, 0x40, 0x00,
            0xB0 + channel, 0x7B, 0x00,
            0xB0 + channel, 0x78, 0x00,
            0xB0 + channel, 0x07, 0x64,
        )
    )


# A byte of an oracle that matches any observed byte: the transaction number
# of a Golem request, which .GOLEM varies on every run. Never a byte the
# commands send at that place otherwise.
ANY = 0xFF


def golem_status_query() -> bytes:
    """GET_STATUS sent by .GOLEM status (since #78), transaction left open."""
    return bytes((0xF0, 0x7D, 0x47, 0x4C, 0x4D, 0x01, ANY, 0x00, 0xF7))


ORACLES = {
    "smoke": bytes.fromhex("91 3c 64 81 3c 00"),
    "mttest": bytes.fromhex("91 3c 64 81 3c 00 f8"),
    "state": bytes.fromhex("f3 01 f9"),
    "api-errors": bytes.fromhex("f6 f9"),
    "no-id": bytes.fromhex("f5 f9"),
    "test1": start_cleanup() + bytes.fromhex("c1 00 91 40 64 91 40 00") + all_notes_off(),
    "testsyx": start_cleanup() + bytes.fromhex("f0 41 10 16 12 20 00 00 54 45 53 54 20 f7") + all_notes_off(),
    "negative": start_cleanup() + bytes.fromhex("c1 00 91 3c 64 81 3c 00") + all_notes_off(),
    "badsyx": start_cleanup() + bytes.fromhex("f0 41 10 16 f7") + all_notes_off(),
    # build-player-image.ps1 -ReturnCheck: F9 is written by BASIC after
    # .uninstall, so it only appears if .GOLEM play returned (issue #1).
    "test1-return": start_cleanup() + bytes.fromhex("c1 00 91 40 64 91 40 00") + all_notes_off() + b"\xf9",
    # build-player-image.ps1 -MemoryCheck: note, TEST1, then F9 only if the
    # BASIC string over $6000-$7FFF is intact after every command (issue #2).
    # .GOLEM status first asks for the Golem state (no reply in CSpect).
    "memory": golem_status_query() + bytes.fromhex("90 3c 64 80 3c 00") + all_notes_off()
    + start_cleanup() + bytes.fromhex("c1 00 91 40 64 91 40 00") + all_notes_off() + b"\xf9",
}


@dataclass(frozen=True)
class Capture:
    data: bytes
    timestamps: list[float]
    source_rows: int


def _find_column(fieldnames: list[str], requested: str | None, candidates: tuple[str, ...]) -> str | None:
    if requested:
        if requested not in fieldnames:
            raise ValueError(f"CSV column not found: {requested!r}")
        return requested
    folded = {name.casefold().strip(): name for name in fieldnames}
    for candidate in candidates:
        if candidate in folded:
            return folded[candidate]
    return None


def _time_scale(column: str, unit: str) -> float:
    if unit != "auto":
        return UNIT_SCALE[unit]
    match = re.search(r"\[(s|ms|us|µs|ns)\]", column, re.IGNORECASE)
    if not match:
        return 1.0
    detected = match.group(1).casefold().replace("µ", "u")
    return UNIT_SCALE[detected]


def parse_byte(value: str, radix: str = "auto") -> int:
    text = value.strip().replace("_", "")
    if radix == "hex" or text.casefold().startswith("0x") or re.search(r"[a-f]", text, re.I):
        number = int(text.removeprefix("0x").removeprefix("0X"), 16)
    elif radix == "decimal":
        number = int(text, 10)
    elif text.casefold().startswith("0b"):
        number = int(text, 2)
    else:
        number = int(text, 10)
    if not 0 <= number <= 0xFF:
        raise ValueError(f"decoded value is not one byte: {value!r}")
    return number


def _is_error(value: str) -> bool:
    return value.strip().casefold() not in ("", "0", "false", "no", "ok", "none")


def read_capture(
    path: Path,
    *,
    time_column: str | None = None,
    value_column: str | None = None,
    direction_column: str | None = None,
    direction: str | None = None,
    time_unit: str = "auto",
    radix: str = "auto",
) -> Capture:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames:
            raise ValueError("CSV has no header")
        fields = list(reader.fieldnames)
        time_name = _find_column(fields, time_column, TIME_COLUMNS)
        if not time_name:
            time_name = next(
                (name for name in fields if "time" in name.casefold() or "stamp" in name.casefold()),
                None,
            )
        value_name = _find_column(fields, value_column, VALUE_COLUMNS)
        direction_name = _find_column(fields, direction_column, DIRECTION_COLUMNS)
        if not time_name:
            raise ValueError("timestamp column not found; use --time-column")
        if not value_name:
            raise ValueError("decoded byte column not found; use --value-column")
        if direction and not direction_name:
            raise ValueError("direction filter requested but no direction column was found")
        error_names = [name for name in fields if name.casefold().strip() in ERROR_WORDS]
        scale = _time_scale(time_name, time_unit)

        data = bytearray()
        timestamps: list[float] = []
        source_rows = 0
        for line_number, row in enumerate(reader, start=2):
            source_rows += 1
            if direction and row.get(direction_name, "").strip().casefold() != direction.casefold():
                continue
            failures = [name for name in error_names if _is_error(row.get(name, ""))]
            if failures:
                raise ValueError(f"UART decoder error on CSV line {line_number}: {', '.join(failures)}")
            try:
                timestamp = float(row[time_name]) * scale
                value = parse_byte(row[value_name], radix)
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(f"invalid CSV line {line_number}: {error}") from error
            if timestamps and timestamp < timestamps[-1]:
                raise ValueError(f"timestamps go backwards on CSV line {line_number}")
            timestamps.append(timestamp)
            data.append(value)
    if not data:
        raise ValueError("capture contains no selected UART bytes")
    return Capture(bytes(data), timestamps, source_rows)


def compare_exact(actual: bytes, expected: bytes) -> tuple[bool, str]:
    """Byte-exact comparison; an ANY byte in expected matches anything."""
    common = min(len(actual), len(expected))
    for index in range(common):
        if expected[index] != ANY and actual[index] != expected[index]:
            return False, (
                f"byte {index}: expected 0x{expected[index]:02X}, "
                f"observed 0x{actual[index]:02X}"
            )
    if len(actual) != len(expected):
        return False, f"length: expected {len(expected)} bytes, observed {len(actual)}"
    return True, f"exact sequence: {len(actual)} bytes"


def timing_rows(
    capture: Capture, profile: str, *, start: int = 0
) -> tuple[list[tuple[str, float, float, float]], int]:
    markers = NOTE_MARKERS if profile == "note" else MARKERS
    found = []
    cursor = start
    for marker in markers:
        index = capture.data.find(marker.message, cursor)
        if index < 0:
            raise ValueError(f"missing MIDI marker: {marker.label}")
        found.append((marker, capture.timestamps[index]))
        cursor = index + len(marker.message)
    if profile == "note":
        return measure_note_durations(found), cursor
    origin = found[0][1]
    return [
        (marker.label, marker.expected_seconds, timestamp - origin, timestamp - origin - marker.expected_seconds)
        for marker, timestamp in found
    ], cursor


def timing_runs(
    capture: Capture, profile: str, count: int
) -> list[list[tuple[str, float, float, float]]]:
    runs = []
    cursor = 0
    for run in range(1, count + 1):
        try:
            rows, cursor = timing_rows(capture, profile, start=cursor)
        except ValueError as error:
            raise ValueError(f"timing run {run}: {error}") from error
        runs.append(rows)
    return runs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--time-column")
    parser.add_argument("--value-column")
    parser.add_argument("--direction-column")
    parser.add_argument("--direction", help="keep only rows with this direction/channel label")
    parser.add_argument("--time-unit", choices=("auto", "s", "ms", "us", "ns"), default="auto")
    parser.add_argument("--radix", choices=("auto", "hex", "decimal"), default="auto")
    check = parser.add_mutually_exclusive_group(required=True)
    check.add_argument("--expect", help="exact hexadecimal bytes, for example '91 3c 64'")
    check.add_argument("--expect-file", type=Path, help="file containing the exact expected bytes")
    check.add_argument("--oracle", choices=tuple(ORACLES), help="named CSpect golden sequence")
    check.add_argument("--profile", choices=("smf", "note"), help="validate a timing marker profile")
    parser.add_argument("--runs", type=int, default=1, help="timing sequences expected in one capture")
    parser.add_argument("--tolerance-ms", type=float, default=50.0)
    parser.add_argument("--report", type=Path, help="write a machine-readable JSON result")
    args = parser.parse_args()

    report: dict[str, object] = {"capture": str(args.capture), "passed": False}
    try:
        capture = read_capture(
            args.capture,
            time_column=args.time_column,
            value_column=args.value_column,
            direction_column=args.direction_column,
            direction=args.direction,
            time_unit=args.time_unit,
            radix=args.radix,
        )
        report.update(bytes=len(capture.data), source_rows=capture.source_rows)
        print(f"decoded {len(capture.data)} bytes from {capture.source_rows} CSV rows")

        if args.profile:
            if args.runs < 1:
                raise ValueError("--runs must be at least 1")
            runs = timing_runs(capture, args.profile, args.runs)
            rows = [row for run_rows in runs for row in run_rows]
            tolerance = args.tolerance_ms / 1000.0
            passed = all(abs(row[3]) <= tolerance for row in rows)
            report["timing"] = [
                {
                    "run": run_number,
                    "event": label,
                    "expected_s": expected,
                    "observed_s": observed,
                    "error_s": error,
                }
                for run_number, run_rows in enumerate(runs, start=1)
                for label, expected, observed, error in run_rows
            ]
            for run_number, run_rows in enumerate(runs, start=1):
                for label, expected, observed, error in run_rows:
                    print(
                        f"run {run_number:02d} {label:13s}: expected={expected:.6f}s "
                        f"observed={observed:.6f}s error={error:+.6f}s"
                    )
            detail = f"{args.runs} run(s), all timing errors within +/-{args.tolerance_ms:.3f} ms"
        else:
            if args.expect_file:
                expected = args.expect_file.read_bytes()
            elif args.oracle:
                expected = ORACLES[args.oracle]
            else:
                expected = bytes.fromhex(args.expect)
            passed, detail = compare_exact(capture.data, expected)
            report.update(expected_hex=expected.hex(" "), observed_hex=capture.data.hex(" "))

        report.update(passed=passed, detail=detail)
        print(("PASS: " if passed else "FAIL: ") + detail, file=sys.stdout if passed else sys.stderr)
    except (OSError, ValueError) as error:
        report["error"] = str(error)
        print(f"FAIL: {error}", file=sys.stderr)
        passed = False

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
