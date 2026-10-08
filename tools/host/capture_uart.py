#!/usr/bin/env python3
"""Capture the CSpect Pi UART TCP stream and verify the smoke-test notes."""

from __future__ import annotations

import argparse
import os
import socket
import sys
import time
from pathlib import Path

EXPECTED = bytes.fromhex("91 3c 64 81 3c 00")


def connect(host: str, port: int, timeout: float) -> socket.socket:
    deadline = time.monotonic() + timeout
    while True:
        try:
            return socket.create_connection((host, port), timeout=0.5)
        except OSError:
            if time.monotonic() >= deadline:
                raise TimeoutError(f"CSpect bridge unavailable at {host}:{port}")
            time.sleep(0.1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=15320)
    parser.add_argument("--connect-timeout", type=float, default=20.0)
    parser.add_argument("--capture-timeout", type=float, default=5.0)
    parser.add_argument(
        "--settle-timeout",
        type=float,
        default=0.25,
        help="after receiving the expectation, keep collecting to reject extra bytes",
    )
    parser.add_argument("--output", type=Path, default=Path("captured-midi.bin"))
    parser.add_argument(
        "--expect",
        default=EXPECTED.hex(" "),
        help="expected hexadecimal byte sequence",
    )
    parser.add_argument(
        "--oracle",
        help="named golden sequence from analyze_uart_capture.py (e.g. test1-return, memory)",
    )
    parser.add_argument(
        "--capture-only",
        action="store_true",
        help="capture until timeout and pass when at least one byte was received",
    )
    parser.add_argument("--quiet", action="store_true", help="do not print each chunk")
    args = parser.parse_args()

    try:
        if args.oracle:
            # Imported here: analyze_uart_capture imports this module indirectly.
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            # NextBuild's embedded Python does not add the script directory to sys.path.
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from analyze_uart_capture import ORACLES, compare_exact

            if args.oracle not in ORACLES:
                parser.error(f"unknown --oracle {args.oracle}; choose from {', '.join(ORACLES)}")
            expected = ORACLES[args.oracle]
        else:
            expected = bytes.fromhex(args.expect)
    except ValueError as error:
        parser.error(f"invalid --expect value: {error}")

    received = bytearray()
    with connect(args.host, args.port, args.connect_timeout) as connection:
        print(f"connected to {args.host}:{args.port}", flush=True)
        connection.settimeout(0.25)
        deadline = time.monotonic() + args.capture_timeout
        while time.monotonic() < deadline and (
            args.capture_only or len(received) < len(expected)
        ):
            try:
                chunk = connection.recv(256)
            except socket.timeout:
                continue
            if not chunk:
                break
            received.extend(chunk)
            if not args.quiet:
                print("RX " + chunk.hex(" "), flush=True)

        if not args.capture_only and len(received) >= len(expected):
            settle_deadline = time.monotonic() + args.settle_timeout
            while time.monotonic() < settle_deadline:
                try:
                    chunk = connection.recv(256)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                received.extend(chunk)
                if not args.quiet:
                    print("RX " + chunk.hex(" "), flush=True)

    args.output.write_bytes(received)
    if args.capture_only:
        if not received:
            print("FAIL: no MIDI bytes captured", file=sys.stderr)
            return 1
        print(f"PASS: captured {len(received)} MIDI bytes")
        return 0
    print("captured: " + bytes(received).hex(" "))
    if args.oracle:
        exact, _ = compare_exact(bytes(received), expected)   # ANY bytes in oracles
    else:
        exact = bytes(received) == expected
    if not exact:
        print("FAIL: expected " + expected.hex(" "), file=sys.stderr)
        return 1
    print("PASS: captured byte sequence is exact")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
