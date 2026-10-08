#!/usr/bin/env python3
"""Compare frame-quantised and millisecond SMF scheduler timing."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from midi_excerpt import scan_track


def read_events(path: Path) -> tuple[int, list[dict[str, object]]]:
    data = path.read_bytes()
    if len(data) < 14 or data[:4] != b"MThd":
        raise ValueError("missing MThd header")
    header_length = int.from_bytes(data[4:8], "big")
    if header_length < 6 or 8 + header_length > len(data):
        raise ValueError("invalid MThd length")
    _smf_format, track_count, division = struct.unpack(">HHH", data[8:14])
    if division == 0 or division & 0x8000:
        raise ValueError("only positive PPQN timing is supported")

    offset = 8 + header_length
    ordered: list[dict[str, object]] = []
    for track_index in range(track_count):
        if offset + 8 > len(data) or data[offset : offset + 4] != b"MTrk":
            raise ValueError(f"missing MTrk chunk {track_index}")
        length = int.from_bytes(data[offset + 4 : offset + 8], "big")
        start = offset + 8
        end = start + length
        if end > len(data):
            raise ValueError(f"truncated MTrk chunk {track_index}")
        events, _tempos = scan_track(data[start:end], track_index)
        for event_index, event in enumerate(events):
            event["track"] = track_index
            event["event"] = event_index
            ordered.append(event)
        offset = end
    if offset != len(data):
        raise ValueError("extra data after declared tracks")
    ordered.sort(key=lambda event: (event["tick"], event["track"], event["event"]))
    return division, ordered


def quantise_50(us: Fraction) -> Fraction:
    return Fraction(int(us / 20_000) * 20_000)


def quantise_60(us: Fraction) -> Fraction:
    cycles = int(us / 50_000)
    remainder = us - cycles * 50_000
    boundary = 0
    if remainder >= 33_334:
        boundary = 33_334
    elif remainder >= 16_667:
        boundary = 16_667
    return Fraction(cycles * 50_000 + boundary)


def quantise_millisecond(us: Fraction) -> Fraction:
    return Fraction(int(us / 1_000) * 1_000)


def analyse(
    path: Path,
    refresh_hz: int,
    scheduler: str = "frame",
) -> dict[str, object]:
    division, events = read_events(path)
    if scheduler == "frame":
        quantise = quantise_50 if refresh_hz == 50 else quantise_60
    elif scheduler == "millisecond":
        quantise = quantise_millisecond
    else:
        raise ValueError("scheduler must be frame or millisecond")
    elapsed_us = Fraction(0)
    current_tick = 0
    tempo = 500_000
    note_times: list[tuple[Fraction, Fraction]] = []
    channel_errors: list[Fraction] = []

    for event in events:
        tick = int(event["tick"])
        if tick > current_tick:
            elapsed_us += Fraction((tick - current_tick) * tempo, division)
            current_tick = tick
        message = event["wire_message"]
        if message is not None:
            actual_us = quantise(elapsed_us)
            channel_errors.append(actual_us - elapsed_us)
            if message[0] & 0xF0 == 0x90 and len(message) == 3 and message[2] != 0:
                note_times.append((elapsed_us, actual_us))
        event_tempo = event["tempo"]
        if event_tempo is not None:
            tempo = int(event_tempo)

    interval_errors: list[Fraction] = []
    collapsed = 0
    positive_subquantum = 0
    quantum_us = (
        Fraction(1_000)
        if scheduler == "millisecond"
        else Fraction(1_000_000, refresh_hz)
    )
    for previous, current in zip(note_times, note_times[1:]):
        ideal_interval = current[0] - previous[0]
        actual_interval = current[1] - previous[1]
        interval_errors.append(actual_interval - ideal_interval)
        if 0 < ideal_interval < quantum_us:
            positive_subquantum += 1
            if actual_interval == 0:
                collapsed += 1

    to_ms = lambda value: round(float(value / 1000), 3)
    return {
        "file_name": path.name,
        "refresh_hz": refresh_hz,
        "scheduler": scheduler,
        "channel_events": len(channel_errors),
        "note_on_events": len(note_times),
        "event_error_ms": {
            "minimum": to_ms(min(channel_errors, default=Fraction(0))),
            "maximum": to_ms(max(channel_errors, default=Fraction(0))),
        },
        "note_interval_error_ms": {
            "minimum": to_ms(min(interval_errors, default=Fraction(0))),
            "maximum": to_ms(max(interval_errors, default=Fraction(0))),
        },
        "positive_note_intervals_shorter_than_quantum": positive_subquantum,
        "short_note_intervals_collapsed_to_zero": collapsed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("midi", type=Path)
    parser.add_argument("--refresh", type=int, choices=(50, 60), required=True)
    parser.add_argument(
        "--scheduler", choices=("frame", "millisecond"), default="frame"
    )
    args = parser.parse_args()
    print(
        json.dumps(
            analyse(args.midi, args.refresh, args.scheduler),
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
