#!/usr/bin/env python3
"""Deterministic mt32-pi Golem responder for the bidirectional CSpect test."""

from __future__ import annotations

import argparse
import socket
import sys
import time
from pathlib import Path

# NextBuild's embedded Python does not add the script directory to sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from golem_protocol import ACCEPTED, ERROR, READY, response

EXPECTED = (
    bytes.fromhex("f0 7d 47 4c 4d 01 01 03 05 00 f7"),
    bytes.fromhex("f0 7d 47 4c 4d 01 01 01 01 f7"),
    bytes.fromhex("f0 7d 47 4c 4d 01 01 02 02 f7"),
    bytes.fromhex("f0 7d 47 4c 4d 01 01 01 00 f7"),
)


def connect(host: str, port: int, deadline: float) -> socket.socket:
    while time.monotonic() < deadline:
        try:
            return socket.create_connection((host, port), timeout=0.5)
        except OSError:
            time.sleep(0.05)
    raise TimeoutError(f"CSpect UART did not listen on {host}:{port}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=15320)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument(
        "--inject-stale", action="store_true", help="precede each reply with transaction 0"
    )
    outcome = parser.add_mutually_exclusive_group()
    outcome.add_argument(
        "--error-index", type=int, help="reply to this zero-based request with ERROR 5"
    )
    outcome.add_argument(
        "--timeout-index", type=int, help="leave this zero-based request unanswered"
    )
    parser.add_argument(
        "--expect-stop",
        action="store_true",
        help="since #4 a failed request stops BASIC: pass only if nothing follows it",
    )
    parser.add_argument(
        "--settle", type=float, default=8.0, help="seconds to wait for unexpected traffic"
    )
    args = parser.parse_args()
    failing = args.error_index if args.error_index is not None else args.timeout_index
    if args.expect_stop and failing is None:
        parser.error("--expect-stop needs --error-index or --timeout-index")
    deadline = time.monotonic() + args.timeout
    sock = connect(args.host, args.port, deadline)
    sock.settimeout(0.5)
    frame = bytearray()
    seen = []
    marker = False
    try:
        stop_deadline = None
        while time.monotonic() < deadline and (len(seen) < len(EXPECTED) or not marker):
            if stop_deadline is not None and time.monotonic() >= stop_deadline:
                break
            try:
                chunk = sock.recv(256)
            except socket.timeout:
                continue
            if not chunk:
                raise ConnectionError("CSpect UART disconnected")
            for value in chunk:
                if value == 0xF0:
                    frame = bytearray((value,))
                    continue
                if frame:
                    frame.append(value)
                    if value != 0xF7:
                        continue
                    request_frame = bytes(frame)
                    frame.clear()
                    index = len(seen)
                    canonical = request_frame[:6] + b"\x01" + request_frame[7:]
                    if index >= len(EXPECTED) or canonical != EXPECTED[index]:
                        raise AssertionError(
                            f"unexpected request {request_frame.hex(' ')} at index {index}"
                        )
                    seen.append(request_frame)
                    transaction = request_frame[6]
                    command = request_frame[7]
                    payload = request_frame[8:-1]
                    if args.expect_stop and index > failing:
                        raise AssertionError(
                            f"request {index} after the failed request {failing}: BASIC did not stop"
                        )
                    if index == args.error_index:
                        sock.sendall(response(transaction, ERROR, command, b"\x05"))
                        if args.expect_stop:
                            stop_deadline = time.monotonic() + args.settle
                        continue
                    if index == args.timeout_index:
                        if args.expect_stop:
                            # .GOLEM waits 1500 frames (25-30 s) before failing.
                            stop_deadline = time.monotonic() + 32.0 + args.settle
                        continue
                    if args.inject_stale:
                        stale_transaction = (transaction + 1) & 0x7F
                        sock.sendall(
                            response(stale_transaction, ACCEPTED, command)
                            + response(stale_transaction, READY, command, payload)
                        )
                    sock.sendall(
                        response(transaction, ACCEPTED, command)
                        + response(transaction, READY, command, payload)
                    )
                elif value == 0xF9:
                    marker = True
                    if args.expect_stop:
                        raise AssertionError("F9 marker after a failed request: BASIC did not stop")
        if args.expect_stop:
            if len(seen) != failing + 1:
                raise TimeoutError(f"expected {failing + 1} request(s) before the stop, saw {len(seen)}")
            print(f"Golem error test passed: request {failing} failed and BASIC stopped")
            return 0
        if len(seen) != len(EXPECTED) or not marker:
            raise TimeoutError(f"incomplete run: requests={len(seen)}, marker={marker}")
    finally:
        sock.close()
    print(f"Golem bidirectional test passed: {len(seen)} transactions + F9")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
