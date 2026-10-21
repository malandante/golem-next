# `.golem note` duration after the raster-line fix (PR #93)

Date: 2026-10-14. Hardware: ZX Spectrum Next, HDMI, 50 Hz, REG 3 = $33
(+2A/+3 timing). Logic analyser on joystick pin 7 (`.golem output left`),
UART decoding at 31250 baud.

Command: `.golem note 60 100 5 2`

| Event | Time (s) |
| --- | --- |
| Note On `91 3C 64` | 24.921509 |
| Note Off `81 3C 00` | 29.922571 |

Measured duration: **5001.1 ms** for a requested 5 s (+0.02 %).

The Note Off is followed by CC 64 = 0, CC 123 and CC 120 on all 16 channels
(`send_note_off`), 51 messages at 320 µs per byte.

Before the fix the same command measured 5055 ms on this Next (2026-10-14),
because `.golem note` counted 50 frames per second while a frame lasts
20.259 ms with +2A/+3 timing.

File: `joy-left-note-5s.csv` (analyser export).
