#!/usr/bin/env python3
"""Validate the MTDURATION raster-bound result from the CSpect UART stream."""

from __future__ import annotations

import argparse
import socket
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from capture_uart import connect


def validate_capture(data: bytes, expected_mode: int, max_lines: int) -> tuple[int, int]:
    """Return observed maximum crossings and CPU-speed index or raise ValueError."""
    marker = data.find(b"\xf2")
    if marker < 0 or marker + 3 > len(data):
        raise ValueError("missing F2 duration marker")
    mode = data[marker + 1]
    lines = data[marker + 2]
    if mode != expected_mode:
        raise ValueError(f"mode {mode}, expected {expected_mode}")
    expected_prefix = b"\xfe" * (512 if expected_mode == 0 else 0)
    if data[:marker] != expected_prefix:
        raise ValueError(
            f"unexpected payload before marker: {len(data[:marker])} byte(s)"
        )
    tail = data[marker + 3 :]
    if len(tail) != 3 or tail[0] != 0xF3 or tail[2] != 0xF9:
        raise ValueError("missing or extra data after duration marker")
    speed = tail[1]
    if speed > 3:
        raise ValueError(f"invalid CPU-speed index {speed}")
    if lines > max_lines:
        raise ValueError(f"{lines} raster crossings exceeds limit {max_lines}")
    return lines, speed


def validate_capture_matrix(
    data: bytes, expected_mode: int, max_lines: int, expected_speeds: tuple[int, ...]
) -> list[tuple[int, int]]:
    """Validate consecutive duration results followed by the autoexec F9 marker."""
    offset = 0
    results: list[tuple[int, int]] = []
    expected_prefix = b"\xfe" * (512 if expected_mode == 0 else 0)
    for expected_speed in expected_speeds:
        prefix_end = offset + len(expected_prefix)
        if data[offset:prefix_end] != expected_prefix:
            raise ValueError(
                f"unexpected payload before CPU-speed index {expected_speed}"
            )
        offset = prefix_end
        if data[offset : offset + 2] != bytes((0xF2, expected_mode)):
            raise ValueError(
                f"missing duration marker for CPU-speed index {expected_speed}"
            )
        if offset + 5 > len(data) or data[offset + 3] != 0xF3:
            raise ValueError(
                f"truncated duration result for CPU-speed index {expected_speed}"
            )
        lines = data[offset + 2]
        speed = data[offset + 4]
        if speed != expected_speed:
            raise ValueError(f"CPU-speed index {speed}, expected {expected_speed}")
        if lines > max_lines:
            raise ValueError(f"{lines} raster crossings exceeds limit {max_lines}")
        results.append((lines, speed))
        offset += 5

    if data[offset:] != b"\xf9":
        raise ValueError("missing or extra data after duration matrix")
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=15320)
    parser.add_argument("--connect-timeout", type=float, default=60.0)
    parser.add_argument("--capture-timeout", type=float, default=10.0)
    parser.add_argument("--expected-mode", type=int, choices=(0, 1), required=True)
    parser.add_argument(
        "--expected-speeds",
        type=int,
        choices=(0, 1, 2, 3),
        nargs="+",
        default=(0,),
        help="CPU-speed indices expected in order (0=3.5, 1=7, 2=14, 3=28)",
    )
    parser.add_argument("--max-lines", type=int, default=32)
    parser.add_argument("--scanlines", type=int, default=312)
    parser.add_argument("--refresh-hz", type=float, default=50.0)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    received = bytearray()
    with connect(args.host, args.port, args.connect_timeout) as connection:
        print(f"connected to {args.host}:{args.port}", flush=True)
        connection.settimeout(0.1)
        deadline = time.monotonic() + args.capture_timeout
        while time.monotonic() < deadline:
            try:
                chunk = connection.recv(1024)
            except socket.timeout:
                continue
            if not chunk:
                break
            received.extend(chunk)
            if not args.quiet:
                print(f"RX {len(chunk)} byte(s)", flush=True)
            if received.endswith(b"\xf9"):
                break

    try:
        if len(args.expected_speeds) == 1:
            results = [
                validate_capture(bytes(received), args.expected_mode, args.max_lines)
            ]
            expected_speed = args.expected_speeds[0]
            if results[0][1] != expected_speed:
                raise ValueError(
                    f"CPU-speed index {results[0][1]}, expected {expected_speed}"
                )
        else:
            results = validate_capture_matrix(
                bytes(received),
                args.expected_mode,
                args.max_lines,
                tuple(args.expected_speeds),
            )
    except ValueError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    path = "16-byte WRITE" if args.expected_mode == 0 else "FIFO-full WRITE"
    for lines, speed in results:
        speed_mhz = (3.5, 7.0, 14.0, 28.0)[speed]
        upper_microseconds = (
            (lines + 1) * 1_000_000.0 / (args.scanlines * args.refresh_hz)
        )
        print(
            f"PASS: {path}, maximum {lines} raster crossing(s); "
            f"duration is below {lines + 1} complete scanline(s) "
            f"({upper_microseconds:.1f} us at {args.refresh_hz:g} Hz/{args.scanlines} lines); "
            f"CPU {speed_mhz:g} MHz"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
