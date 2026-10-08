#!/usr/bin/env python3
"""Summarise what an SMF does before its first Note On (#14).

Prints the file size, how many SysEx and other bytes are sent before the first
Note On, when that note is due according to the tempo map, and how long the
preceding bytes need on the MIDI wire (31250 baud, 10 bits per byte). Useful to
tell the player's load time apart from a long silent or SysEx-heavy intro.
The last line sends every event as soon as it is due and the cable is free,
which is what .GOLEM play does, so a SysEx that is still being sent delays
everything after it.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

WIRE_BYTES_PER_SECOND = 3125


def read_vlq(data: bytes, pos: int) -> tuple[int, int]:
    value = 0
    for _ in range(4):
        byte = data[pos]
        pos += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, pos
    raise ValueError("VLQ longer than 4 bytes")


def track_events(data: bytes):
    """Yield (tick, kind, wire_bytes, tempo) for one MTrk payload."""
    pos, tick, running = 0, 0, 0
    while pos < len(data):
        delta, pos = read_vlq(data, pos)
        tick += delta
        status = data[pos]
        if status == 0xFF:
            kind, pos = data[pos + 1], pos + 2
            length, pos = read_vlq(data, pos)
            tempo = int.from_bytes(data[pos:pos + 3], "big") if kind == 0x51 else None
            pos += length
            running = 0
            yield tick, "meta", 0, tempo
            if kind == 0x2F:
                return
        elif status in (0xF0, 0xF7):
            length, pos = read_vlq(data, pos + 1)
            pos += length
            running = 0
            yield tick, "sysex", length + (1 if status == 0xF0 else 0), None
        else:
            if status & 0x80:
                running = status
                pos += 1
            size = 1 if running & 0xF0 in (0xC0, 0xD0) else 2
            velocity = data[pos + 1] if size == 2 else 0
            pos += size
            if running & 0xF0 == 0x90 and velocity:
                yield tick, "note_on", 1 + size, (running & 0x0F, data[pos - 2], velocity)
            else:
                yield tick, "channel", 1 + size, None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("midi", type=Path)
    args = parser.parse_args()
    smf = args.midi.read_bytes()
    if smf[:4] != b"MThd":
        raise SystemExit("not an SMF")
    header_length, _fmt, _tracks, division = struct.unpack(">IHHH", smf[4:14])
    if division & 0x8000:
        raise SystemExit("SMPTE timing not supported")
    pos, events = 8 + header_length, []
    while pos + 8 <= len(smf):
        chunk, length = smf[pos:pos + 4], struct.unpack(">I", smf[pos + 4:pos + 8])[0]
        if chunk == b"MTrk":
            events.extend(track_events(smf[pos + 8:pos + 8 + length]))
        pos += 8 + length
    events.sort(key=lambda event: event[0])
    first_note = next((event[0] for event in events if event[1] == "note_on"), None)
    if first_note is None:
        raise SystemExit("no Note On in the file")

    seconds, last_tick, tempo = 0.0, 0, 500000
    sysex_count = sysex_bytes = other_bytes = 0
    wire_free = 0.0  # when the MIDI cable is idle again, sending in file order
    for tick, kind, wire, new_tempo in events:
        if tick > first_note:
            break
        seconds += (tick - last_tick) * tempo / division / 1e6
        last_tick = tick
        if new_tempo and kind == "meta":
            tempo = new_tempo
        if tick == first_note and kind == "note_on":
            break
        if wire:
            wire_free = max(seconds, wire_free) + wire / WIRE_BYTES_PER_SECOND
        if kind == "sysex":
            sysex_count += 1
            sysex_bytes += wire
        else:
            other_bytes += wire

    wire_seconds = (sysex_bytes + other_bytes) / WIRE_BYTES_PER_SECOND
    print(f"{args.midi.name}: {len(smf)} bytes, {(len(smf) + 8191) // 8192} banks of 8K")
    print(f"Before the first Note On: {sysex_count} SysEx ({sysex_bytes} bytes), {other_bytes} other bytes")
    print(f"First Note On due at {seconds:.2f} s by the tempo map")
    print(f"Bytes before it need at least {wire_seconds:.2f} s at 31250 baud")
    print(f"With the cable busy, the first Note On leaves at {max(seconds, wire_free):.2f} s")

    # The first Note On may not be audible (a muted part, or a channel the
    # MT-32 ignores by default: 1 and 11-16), so list the first ones.
    print("First Note Ons (time by the tempo map, MIDI channel 1-16, note, velocity):")
    seconds, last_tick, tempo, shown = 0.0, 0, 500000, 0
    for tick, kind, _wire, extra in events:
        seconds += (tick - last_tick) * tempo / division / 1e6
        last_tick = tick
        if kind == "meta" and extra:
            tempo = extra
        elif kind == "note_on":
            channel, note, velocity = extra
            print(f"  {seconds:7.2f} s  ch {channel + 1:2}  note {note:3}  vel {velocity:3}")
            shown += 1
            if shown == 12:
                break


if __name__ == "__main__":
    main()
