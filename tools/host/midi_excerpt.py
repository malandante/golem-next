#!/usr/bin/env python3
"""Create a local test excerpt from an external SMF without re-timing events."""

from __future__ import annotations

import argparse
import struct
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from midi_manifest import read_vlq


def encode_vlq(value: int) -> bytes:
    if value < 0 or value > 0x0FFFFFFF:
        raise ValueError("VLQ value is outside the four-byte SMF range")
    encoded = bytearray([value & 0x7F])
    value >>= 7
    while value:
        encoded.append(0x80 | (value & 0x7F))
        value >>= 7
    encoded.reverse()
    return bytes(encoded)


def scan_track(data: bytes, track_index: int) -> tuple[list[dict[str, object]], list[tuple[int, int, int, int]]]:
    offset = 0
    tick = 0
    running_status: int | None = None
    events: list[dict[str, object]] = []
    tempos: list[tuple[int, int, int, int]] = []

    while offset < len(data):
        start = offset
        delta, offset = read_vlq(data, offset, len(data))
        tick += delta
        if offset >= len(data):
            raise ValueError("track ends before event status")

        status = data[offset]
        if status & 0x80:
            offset += 1
            if status < 0xF0:
                running_status = status
            else:
                running_status = None
        elif running_status is None:
            raise ValueError("running status without channel status")
        else:
            status = running_status

        meta_type: int | None = None
        tempo: int | None = None
        wire_message: bytes | None = None
        if status < 0xF0:
            length = 1 if status & 0xE0 == 0xC0 else 2
            if offset + length > len(data):
                raise ValueError("truncated channel event")
            if any(value & 0x80 for value in data[offset : offset + length]):
                raise ValueError("invalid channel data byte")
            wire_message = bytes([status]) + data[offset : offset + length]
            offset += length
        elif status == 0xFF:
            if offset >= len(data):
                raise ValueError("truncated meta event")
            meta_type = data[offset]
            offset += 1
            length, offset = read_vlq(data, offset, len(data))
            end = offset + length
            if end > len(data):
                raise ValueError("truncated meta payload")
            if meta_type == 0x51 and length == 3:
                tempo = int.from_bytes(data[offset:end], "big")
            offset = end
        elif status in (0xF0, 0xF7):
            length, offset = read_vlq(data, offset, len(data))
            offset += length
            if offset > len(data):
                raise ValueError("truncated SysEx payload")
        else:
            raise ValueError(f"unsupported SMF status 0x{status:02X}")

        event_index = len(events)
        events.append(
            {
                "tick": tick,
                "raw": data[start:offset],
                "meta_type": meta_type,
                "tempo": tempo,
                "wire_message": wire_message,
            }
        )
        if tempo is not None:
            tempos.append((tick, track_index, event_index, tempo))

    return events, tempos


def tick_at_seconds(seconds: Fraction, ppqn: int, tempos: list[tuple[int, int, int, int]]) -> int:
    target_us = seconds * 1_000_000
    elapsed_us = Fraction(0)
    current_tick = 0
    current_tempo = 500_000
    for tick, _track, _event, tempo in sorted(tempos):
        segment_us = Fraction((tick - current_tick) * current_tempo, ppqn)
        if elapsed_us + segment_us >= target_us:
            remaining = target_us - elapsed_us
            return current_tick + int((remaining * ppqn) / current_tempo)
        elapsed_us += segment_us
        current_tick = tick
        current_tempo = tempo
    remaining = target_us - elapsed_us
    if remaining < 0:
        return current_tick
    return current_tick + int((remaining * ppqn) / current_tempo)


def crop_smf(source: Path, destination: Path, seconds: Fraction) -> dict[str, int]:
    data = source.read_bytes()
    if len(data) < 14 or data[:4] != b"MThd":
        raise ValueError("missing MThd header")
    header_length = int.from_bytes(data[4:8], "big")
    if header_length < 6 or 8 + header_length > len(data):
        raise ValueError("invalid MThd length")
    _smf_format, track_count, division = struct.unpack(">HHH", data[8:14])
    if division == 0 or division & 0x8000:
        raise ValueError("only positive PPQN timing is supported")

    offset = 8 + header_length
    tracks: list[list[dict[str, object]]] = []
    tempos: list[tuple[int, int, int, int]] = []
    for track_index in range(track_count):
        if offset + 8 > len(data) or data[offset : offset + 4] != b"MTrk":
            raise ValueError(f"missing MTrk chunk {track_index}")
        length = int.from_bytes(data[offset + 4 : offset + 8], "big")
        start = offset + 8
        end = start + length
        if end > len(data):
            raise ValueError(f"truncated MTrk chunk {track_index}")
        events, track_tempos = scan_track(data[start:end], track_index)
        tracks.append(events)
        tempos.extend(track_tempos)
        offset = end
    if offset != len(data):
        raise ValueError("extra data after declared tracks")

    end_tick = tick_at_seconds(seconds, division, tempos)
    output = bytearray(data[: 8 + header_length])
    retained_events = 0
    for events in tracks:
        body = bytearray()
        last_tick = 0
        ended = False
        for event in events:
            tick = int(event["tick"])
            if tick > end_tick:
                break
            body.extend(event["raw"])
            retained_events += 1
            last_tick = tick
            if event["meta_type"] == 0x2F:
                ended = True
                break
        if not ended:
            body.extend(encode_vlq(end_tick - last_tick))
            body.extend(b"\xFF\x2F\x00")
        output.extend(b"MTrk")
        output.extend(len(body).to_bytes(4, "big"))
        output.extend(body)

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(output)
    return {
        "end_tick": end_tick,
        "bytes": len(output),
        "tracks": track_count,
        "retained_events": retained_events,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--seconds", type=str, required=True)
    args = parser.parse_args()

    seconds = Fraction(args.seconds)
    if seconds <= 0:
        parser.error("--seconds must be positive")
    result = crop_smf(args.source, args.destination, seconds)
    print(
        f"Wrote local excerpt: {args.destination} "
        f"({result['bytes']} bytes, {result['end_tick']} ticks, "
        f"{result['retained_events']} retained events)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
