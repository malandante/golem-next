#!/usr/bin/env python3
"""Measure TESTTIM.MID event timing from the CSpect UART TCP stream."""

from __future__ import annotations

import argparse
import csv
import socket
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from capture_uart import connect


@dataclass(frozen=True)
class Marker:
    label: str
    message: bytes
    expected_seconds: float


MARKERS = (
    Marker("C on", bytes.fromhex("91 3c 64"), 0.0),
    Marker("C off", bytes.fromhex("81 3c 00"), 0.5),
    Marker("D on", bytes.fromhex("91 3e 64"), 0.5),
    Marker("D off", bytes.fromhex("81 3e 00"), 0.9),
    Marker("E on", bytes.fromhex("91 40 64"), 0.9),
    Marker("E off", bytes.fromhex("81 40 00"), 1.9),
)

NOTE_MARKERS = (
    Marker("low on", bytes.fromhex("90 00 01"), 0.0),
    Marker("low off", bytes.fromhex("80 00 00"), 1.0),
    Marker("high on", bytes.fromhex("9f 7f 7f"), 1.0),
    Marker("high off", bytes.fromhex("8f 7f 00"), 2.0),
)


def find_markers(
    data: bytes, timestamps: list[float], markers: tuple[Marker, ...] = MARKERS
) -> list[tuple[Marker, float]]:
    """Find the ordered markers and return each status-byte timestamp."""
    found: list[tuple[Marker, float]] = []
    cursor = 0
    for marker in markers:
        index = data.find(marker.message, cursor)
        if index < 0:
            raise ValueError(f"missing MIDI marker: {marker.label}")
        found.append((marker, timestamps[index]))
        cursor = index + len(marker.message)
    return found


def measure_note_durations(
    found: list[tuple[Marker, float]],
) -> list[tuple[str, float, float, float]]:
    """Measure each NOTE_MARKERS on/off pair independently."""
    rows = []
    for label, on_index, off_index in (("low", 0, 1), ("high", 2, 3)):
        observed = found[off_index][1] - found[on_index][1]
        rows.append((f"{label} duration", 1.0, observed, observed - 1.0))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=15320)
    parser.add_argument("--connect-timeout", type=float, default=60.0)
    parser.add_argument("--capture-timeout", type=float, default=5.0)
    parser.add_argument("--tolerance", type=float, default=0.04)
    parser.add_argument("--profile", choices=("smf", "note"), default="smf")
    parser.add_argument("--output", type=Path, default=Path("timing.csv"))
    args = parser.parse_args()
    markers = NOTE_MARKERS if args.profile == "note" else MARKERS

    received = bytearray()
    timestamps: list[float] = []
    with connect(args.host, args.port, args.connect_timeout) as connection:
        print(f"connected to {args.host}:{args.port}", flush=True)
        connection.settimeout(0.1)
        deadline = time.monotonic() + args.capture_timeout
        while time.monotonic() < deadline:
            try:
                chunk = connection.recv(256)
            except socket.timeout:
                continue
            if not chunk:
                break
            observed = time.monotonic()
            received.extend(chunk)
            timestamps.extend([observed] * len(chunk))
            print("RX " + chunk.hex(" "), flush=True)
            if markers[-1].message in received:
                break

    try:
        found = find_markers(bytes(received), timestamps, markers)
    except ValueError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    rows = []
    failed = False
    if args.profile == "note":
        rows = measure_note_durations(found)
    else:
        origin = found[0][1]
        for marker, timestamp in found:
            observed = timestamp - origin
            error = observed - marker.expected_seconds
            rows.append((marker.label, marker.expected_seconds, observed, error))

    for label, expected, observed, error in rows:
        failed = failed or abs(error) > args.tolerance
        print(
            f"{label:13s}: expected={expected:.3f}s "
            f"observed={observed:.3f}s error={error:+.3f}s"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("event", "expected_seconds", "observed_seconds", "error_seconds"))
        writer.writerows(rows)

    if failed:
        print(f"FAIL: timing exceeded +/-{args.tolerance:.3f}s", file=sys.stderr)
        return 1
    print(f"PASS: all events within +/-{args.tolerance:.3f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
