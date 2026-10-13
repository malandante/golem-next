# golem-next release notes

## 1.1.0 — 13 October 2026

### New

- **MIDI out through a joystick port.** `.golem output left` or `right` sends
  the MIDI out of pin 7 of that port, for an external MIDI synth without a Pi;
  `.golem output golem` goes back to the Golem and `.golem output` reports the
  current choice. It applies to everything that uses the driver (`.golem`,
  `.gsq`, games) until the driver is uninstalled or the Next restarts. With a
  joystick output, `.mt32` and `.gm` do not ask the Golem first. The signal is
  3.3 V and the cable is not ready yet: do not wire a MIDI DIN cable to the
  joystick port yourself.
- **Driver ABI 0.3.** New function `SET_OUTPUT` (7). `QUERY` returns
  `DE=$0003`, the capabilities in `L` (new bit 2) and the output in `H`.
  `STATUS` returns the raw UART status byte in `B` (receive errors). ABI 0.2
  programs work unchanged.
- `.golem status` shows the output and warns about receive errors
  ("RX errors").
- `.golem play` (and `.mt32`/`.gm play`) says `Golem: playing (SPACE stops)`
  once the file is loaded and the song starts. The MIDI output is unchanged.
- Programmer's guide (`docs/programming.md`, also in the SD package): dot
  commands from BASIC, the GSEQ library from ZX Basic and assembler, and the
  driver calls.

### Documentation

- User guide: engine, ROM set and SoundFont chosen from the Next are not saved
  on the Pi; its defaults come from `mt32-pi.cfg`.
- User guide: with the MT-32 engine, `.golem note` needs a channel from 2 to 10;
  channel 1 is silent.

### Tested

- **CSpect:** driver state preservation, API errors, full FIFO and partial
  writes, missing and already-taken driver ID.
- **ZX Spectrum Next** (core 3.02.01, 50 Hz, HDMI) with the Golem on a
  Raspberry Pi: byte-exact output through pin 7 of each joystick port
  (LA1010, `tests/hardware/results/2026-10-13-joystick-output/`), back to the
  Golem with nothing on the joystick, and `.golem status` with the Golem on.

### Known limitations

- The driver ID `$2D` is still experimental.
- The joystick output has no cable yet and has not been tried with a real
  synth.
- With the Pi switched off, `.golem status` says "no answer", the same as with
  an external synth: the receive line stays idle, so the driver cannot tell
  them apart.
- A note held by the Golem when the Next is switched off mid-song can sound
  again later; only restarting the Pi clears it.

## 1.0.0 — 8 October 2026

First public release.

### Contents of the SD package

| File | Goes to | What it is |
| --- | --- | --- |
| `nextzxos/GOLEM.DRV` | `c:/nextzxos/` | NextZXOS driver: sends MIDI to the Golem and reads its replies (ABI 0.2 in 1.0.0). |
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
  supported in this release (see 1.1.0).
- A note held by the Golem when the Next is switched off mid-song can sound
  again later; no MIDI message clears it, only restarting the Pi.

### Licences

golem-next is MIT licensed. The Golem firmware is a separate program under
GPL-3.0; its source is at https://github.com/malandante/mt32-pi. No Roland ROMs,
SoundFonts or commercial music are included.
