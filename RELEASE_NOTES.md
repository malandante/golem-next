# golem-next release notes

## 1.0.0 — 8 October 2026

First public release.

### Contents of the SD package

| File | Goes to | What it is |
| --- | --- | --- |
| `nextzxos/GOLEM.DRV` | `c:/nextzxos/` | NextZXOS driver: sends MIDI to the Golem and reads its replies (ABI 0.2). |
| `dot/GOLEM` | `c:/dot/` | Plays MIDI files (SMF 0/1, up to 24 tracks and 1 MB) and test notes; sets the Golem engine, ROM set and SoundFont; `status` asks the Golem for its state. |
| `dot/MT32`, `dot/GM` | `c:/dot/` | The same command; `play` and `note` first switch the Golem to MT-32 or to General MIDI. Without a Golem answer they play anyway, for an external synth. |
| `dot/GSQ` | `c:/dot/` | Plays GSEQ files (P pauses, SPACE stops). |
| `lib/GSEQ*.BIN`, `lib/gseq.bas`, `lib/gseq.s` | your program | GSEQ music library: one 8K bank per slot address, a ZX Basic binding and the assembler source. |
| `tools/gseq.py` | your PC | MIDI to GSEQ converter (Python 3). |
| `docs/` | — | User guide (English and Spanish), GSEQ format and API, driver API, Golem protocol. |
| `SHA256SUMS` | — | Hashes of every file in the package. |

The package is built by `tools/release/build_release.py` from the tagged
sources. The CI release build uses sjasmplus 1.24.0; SNasm gives the same
binaries (`--assembler snasm`), which can be checked against `SHA256SUMS`.

### Tested on hardware

- **Setup:** ZX Spectrum Next, core 3.02.01, HDMI, with a Raspberry Pi 3
  running the Golem firmware (mt32-pi 0.13.1 plus the Golem control protocol),
  over UART and I²S.
- **Synthesis and control:** MT-32 and General MIDI playback; engine, ROM set and
  SoundFont changes; `.golem status`.
- **Game music:** the GSEQ library playing the music of a full game in
  development, with pause, song changes and sound effects.
- **Analyser captures of the Next UART output** (LA1010, through the joystick
  port, `tests/hardware/results/2026-10-08-joystick/`):
  - Byte-exact output for notes, test songs and SysEx, at 31250 baud.
  - Event timing at 50 and 60 Hz: intervals exact to 0.05 ms and run-to-run
    jitter under 0.15 ms.

### Known limitations

- The driver ID `$2D` is still experimental; an official ID is being requested
  from the NextZXOS maintainers. Programs should keep calling the driver through
  the constants in `lib/mt32_api.inc`.
- The Golem side (its UART replies and the I²S audio) has been tested by ear
  and by protocol behaviour, not yet captured with the analyser. Tests so far
  used a Raspberry Pi 3; a Pi 4 is expected to behave the same but has not been
  measured.
- MIDI out through the joystick port works at the signal level
  (`REG 11,161`, 3.3 V) but needs a cable that does not exist yet; it is not
  supported in this release.
- A note held by the Golem when the Next is switched off mid-song can sound
  again later; no MIDI message clears it, only restarting the Pi.

### Licences

golem-next is MIT licensed. The Golem firmware is a separate program under
GPL-3.0; its source is at https://github.com/malandante/mt32-pi. No Roland ROMs,
SoundFonts or commercial music are included.
