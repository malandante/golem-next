#!/usr/bin/env python3
"""Writes DRY.MID and EFFECTS.MID: FluidSynth reverb and chorus send per channel.

DRY.MID sets reverb (CC91) and chorus (CC93) to 0 on the 16 channels, for a
dry piano when playing a keyboard on the Golem. EFFECTS.MID sets them back to
the General MIDI defaults (reverb 40, chorus 0). Play either with .golem play
or .gm play; the settings last until the next play resets the synth.

    python3 tools/host/fx_midi.py src/midi
"""
import struct
import sys
from pathlib import Path


def smf(reverb: int, chorus: int) -> bytes:
    events = bytearray()
    for channel in range(16):
        events += bytes([0, 0xB0 | channel, 91, reverb])
        events += bytes([0, 0xB0 | channel, 93, chorus])
    events += bytes([0, 0xFF, 0x2F, 0])
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, 96)
    return header + b"MTrk" + struct.pack(">I", len(events)) + bytes(events)


FILES = {"DRY.MID": smf(0, 0), "EFFECTS.MID": smf(40, 0)}


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    for name, data in FILES.items():
        (out / name).write_bytes(data)
        print(f"{out / name}: {len(data)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
