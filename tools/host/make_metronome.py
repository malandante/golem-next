#!/usr/bin/env python3
"""Write a click-track SMF for checking tempo against a real metronome (#7).

Default: 120 BPM for 3 minutes, MIDI channel 10 (MT-32 rhythm part in the
standard channel map), cowbell on beat 1 of each bar and rim shot on the
others. Start a metronome at the same BPM on the first click and listen for
drift: 1 % fast or slow is about one beat per 50 beats.

With --pad-kb N (#14) the file becomes format 1 with a second track before the
clicks: one text meta event per beat, padded so that the track takes about N KB.
The clicks then sit past the 64 KB mark and the player alternates between two
places of the file far apart on every beat, so it changes 8K bank constantly.
It must sound exactly like the unpadded file.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

PPQN = 480


def vlq(value: int) -> bytes:
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.insert(0, 0x80 | (value & 0x7F))
        value >>= 7
    return bytes(out)


def build(bpm: int, seconds: int, accent: int, click: int, pad_kb: int = 0) -> bytes:
    beats = bpm * seconds // 60
    gate = PPQN // 8
    track = bytearray()
    track += vlq(0) + bytes([0xFF, 0x51, 3]) + (60_000_000 // bpm).to_bytes(3, "big")
    track += vlq(0) + bytes([0xC9, 0])                      # standard rhythm set
    delta = 0
    for beat in range(beats):
        note = accent if beat % 4 == 0 else click
        velocity = 127 if beat % 4 == 0 else 96
        track += vlq(delta) + bytes([0x99, note, velocity])
        track += vlq(gate) + bytes([0x89, note, 0])
        delta = PPQN - gate                                     # to the next click
    track += vlq(0) + bytes([0xFF, 0x2F, 0])
    if not pad_kb:
        header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, PPQN)
        return header + b"MTrk" + struct.pack(">I", len(track)) + bytes(track)
    size = max(16, pad_kb * 1024 // beats)
    text = bytearray()
    for beat in range(beats):
        label = f"beat {beat + 1} ".encode("ascii")
        body = (label * (size // len(label) + 1))[:size]
        text += vlq(0 if beat == 0 else PPQN) + bytes([0xFF, 0x01]) + vlq(size) + body
    text += vlq(0) + bytes([0xFF, 0x2F, 0])
    header = b"MThd" + struct.pack(">IHHH", 6, 1, 2, PPQN)
    return (header + b"MTrk" + struct.pack(">I", len(text)) + bytes(text)
            + b"MTrk" + struct.pack(">I", len(track)) + bytes(track))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bpm", type=int, default=120)
    parser.add_argument("--seconds", type=int, default=180)
    parser.add_argument("--accent", type=int, default=56, help="rhythm key on beat 1 (56 cowbell)")
    parser.add_argument("--click", type=int, default=37, help="rhythm key on other beats (37 rim shot)")
    parser.add_argument("--pad-kb", type=int, default=0, help="add a text track of about N KB before the clicks (#14)")
    parser.add_argument("--output", type=Path, default=Path("METRO120.MID"))
    args = parser.parse_args()
    data = build(args.bpm, args.seconds, args.accent, args.click, args.pad_kb)
    args.output.write_bytes(data)
    print(f"{args.output}: {len(data)} bytes, {args.bpm * args.seconds // 60} beats")


if __name__ == "__main__":
    main()
