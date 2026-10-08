#!/usr/bin/env python3
"""Create a local-only manifest for externally supplied Standard MIDI Files."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path


def read_vlq(data: bytes, offset: int, limit: int) -> tuple[int, int]:
    value = 0
    for _ in range(4):
        if offset >= limit:
            raise ValueError("truncated VLQ")
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, offset
    raise ValueError("VLQ exceeds four bytes")


def parse_track(data: bytes, track_index: int) -> dict[str, object]:
    offset = 0
    tick = 0
    running_status: int | None = None
    event_index = 0
    channel_events = 0
    sysex_events = 0
    sysex_bytes = 0
    sysex_messages: list[dict[str, object]] = []
    tempo_events: list[tuple[int, int, int, int]] = []

    while offset < len(data):
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

        if status < 0xF0:
            data_length = 1 if status & 0xE0 == 0xC0 else 2
            if offset + data_length > len(data):
                raise ValueError("truncated channel event")
            if any(value & 0x80 for value in data[offset : offset + data_length]):
                raise ValueError("invalid channel data byte")
            offset += data_length
            channel_events += 1
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
                microseconds = int.from_bytes(data[offset:end], "big")
                tempo_events.append((tick, track_index, event_index, microseconds))
            offset = end
        elif status in (0xF0, 0xF7):
            length, offset = read_vlq(data, offset, len(data))
            end = offset + length
            if end > len(data):
                raise ValueError("truncated SysEx payload")
            payload = data[offset:end]
            sysex_messages.append(
                {
                    "track": track_index,
                    "event": event_index,
                    "tick": tick,
                    "status": f"{status:02X}",
                    "payload_hex": payload.hex(" ").upper(),
                    "payload_bytes": length,
                }
            )
            offset = end
            sysex_events += 1
            sysex_bytes += length
        else:
            raise ValueError(f"unsupported SMF status 0x{status:02X}")
        event_index += 1

    return {
        "end_tick": tick,
        "events": event_index,
        "channel_events": channel_events,
        "sysex_events": sysex_events,
        "sysex_payload_bytes": sysex_bytes,
        "sysex_messages": sysex_messages,
        "tempo_events": tempo_events,
    }


def duration_seconds(max_tick: int, ppqn: int, tempos: list[tuple[int, int, int, int]]) -> float:
    elapsed = Fraction(0)
    current_tick = 0
    current_tempo = 500_000
    for tick, _track, _event, tempo in sorted(tempos):
        if tick > max_tick:
            break
        if tick > current_tick:
            elapsed += Fraction((tick - current_tick) * current_tempo, ppqn)
            current_tick = tick
        current_tempo = tempo
    elapsed += Fraction((max_tick - current_tick) * current_tempo, ppqn)
    return round(float(elapsed / 1_000_000), 6)


def inspect_smf(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    if len(data) < 14 or data[:4] != b"MThd":
        raise ValueError("missing MThd header")
    header_length = int.from_bytes(data[4:8], "big")
    if header_length < 6 or 8 + header_length > len(data):
        raise ValueError("invalid MThd length")
    smf_format, declared_tracks, division = struct.unpack(">HHH", data[8:14])
    if division & 0x8000:
        raise ValueError("SMPTE division is not supported by this manifest tool")
    if division == 0:
        raise ValueError("zero PPQN division")

    offset = 8 + header_length
    tracks = []
    for track_index in range(declared_tracks):
        if offset + 8 > len(data) or data[offset : offset + 4] != b"MTrk":
            raise ValueError(f"missing MTrk chunk {track_index}")
        length = int.from_bytes(data[offset + 4 : offset + 8], "big")
        start = offset + 8
        end = start + length
        if end > len(data):
            raise ValueError(f"truncated MTrk chunk {track_index}")
        tracks.append(parse_track(data[start:end], track_index))
        offset = end
    if offset != len(data):
        raise ValueError("extra data after declared tracks")

    tempos = [event for track in tracks for event in track["tempo_events"]]
    max_tick = max((int(track["end_tick"]) for track in tracks), default=0)
    return {
        "file_name": path.name,
        "sha256": hashlib.sha256(data).hexdigest().upper(),
        "bytes": len(data),
        "smf_format": smf_format,
        "tracks": declared_tracks,
        "timing": "PPQN",
        "ticks_per_quarter": division,
        "end_tick": max_tick,
        "duration_seconds": duration_seconds(max_tick, division, tempos),
        "events": sum(int(track["events"]) for track in tracks),
        "channel_events": sum(int(track["channel_events"]) for track in tracks),
        "tempo_events": len(tempos),
        "sysex_events": sum(int(track["sysex_events"]) for track in tracks),
        "sysex_payload_bytes": sum(
            int(track["sysex_payload_bytes"]) for track in tracks
        ),
        "sysex_messages": [
            message for track in tracks for message in track["sysex_messages"]
        ],
    }


def file_identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {
        "file_name": path.name,
        "sha256": hashlib.sha256(data).hexdigest().upper(),
        "bytes": len(data),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("midi", type=Path)
    parser.add_argument("--companion", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--provenance", required=True)
    parser.add_argument("--game-version", default="pending")
    parser.add_argument("--rom-version", default="pending")
    parser.add_argument("--expected", required=True)
    args = parser.parse_args()

    manifest = {
        "schema": "mt32-next-local-midi-manifest-v1",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "distribution": "local-only; source files are not copied into the repository",
        "title": args.title,
        "provenance": args.provenance,
        "game_version": args.game_version,
        "rom_version": args.rom_version,
        "expected_result": args.expected,
        "midi": inspect_smf(args.midi),
        "companion": file_identity(args.companion) if args.companion else None,
        "validation": {
            "complete_playback": "pending",
            "timbres_reviewed": "pending",
            "clean_ending": "pending",
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote local manifest: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
