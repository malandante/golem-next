# golem-next release notes

## 1.2.0 — 21 October 2026

Use it with the Golem firmware golem-1.2.0 (https://github.com/malandante/mt32-pi/releases),
the first published since golem-1.0.1: `.golem usb`, `set`, `save`, `bank`
and `loud` need it, and an older firmware answers "firmware too old".

### New

- **`.golem usb [off|on|bridge]`:** MIDI from the Next also goes to USB MIDI
  devices on the Pi (`on`), or only to them (`bridge`, the Golem stays
  silent). Without a word it reports the mode and the number of devices.
- **`play` resets the synth before each song** (MT-32 reset and GM System
  On), so SysEx loaded by one song no longer changes the next one.
  **`.golem reset`** does the same on demand.
- **A MIDI keyboard on the Pi is heard between programs:** with the Golem
  output, the driver leaves the Pi's audio on after a program ends;
  `.golem output golem` turns it on at once (put it in the autoexec).
- **`.golem set volume|fx|channels|thru|keys [value]`:** settings kept by the
  Golem firmware, which survive `play` and the reset SysEx of songs: master
  volume 0–100 (what a Pi HAT's encoder changes), FluidSynth reverb and chorus
  on/off, MT-32 channels standard/alternate (keyboards fixed on channel 1),
  USB keyboard thru, and `keys`: a USB keyboard on the Pi also reaches the
  Next, for programs that read MIDI. Without a value it reports.
- **`.golem save [clear]`:** the Golem keeps its current settings (engine,
  ROM set, SoundFont, `set` and `usb`) for its next start, in `golem.cfg` on
  the Pi's SD card; `clear` deletes it.
- **MIDI input for programs** (`lib/midiin.bas`, `lib/midiin.s`): whole MIDI
  messages from a USB keyboard on the Golem (`.golem set keys on`) or a DIN
  keyboard on a joystick port's MIDI IN, with running status, real-time bytes
  and SysEx handled and the Golem's replies dropped. **`.midimon`** (and its ZX
  Basic version `examples/midimon.bas`) shows what arrives, in hexadecimal.
  *[`.midimon` checked on hardware; the ZX Basic version, pitch bend and the
  modulation wheel only in the simulator]*
- **Help on the Next:** `.golem` alone prints a one-line summary; the full help
  is `GOLEM.GDE` (copy it to `c:/docs/guides/`), opened with `.guide golem`.
- **`.golem set loud on`:** the Golem louder without distortion, through a
  limiter, so a game's music is not buried under its PCM effects through
  HDMI (where the Next gives the Golem half the weight of its DAC). Needs
  firmware golem-1.2.0.
- **OPL3 engine:** `.golem engine opl3` (or **`.opl3 play song.mid`**) plays
  General MIDI with OPL3 FM synthesis, the sound of a Sound Blaster 16, on
  the Golem (libADLMIDI, Nuked OPL3 emulator); `.golem bank` chooses
  one of its 79 instrument banks, or your own WOPL banks from the `opl3`
  folder of the Pi's SD card (79 onwards). `.golem status` names it.
  Needs firmware golem-1.2.0.
- **`DRY.MID` and `EFFECTS.MID`** (package `midi/` folder): reverb and chorus
  off, and back, for other players; with `.golem`, `set fx` lasts longer.

### Fixed

- Stopping `.golem play` with SPACE could leave notes sounding: with SPACE
  still held, the cleanup gave up as soon as it had to wait for the driver,
  and the Note Offs reached channels 0-6 only. Channels 8-16 (drums included)
  kept their notes. The whole sweep is now sent.
- `.golem note` lasted about 1% too long: it counted 50 frames per second
  instead of real milliseconds.
- With a joystick output, the port stays in UART mode after a program ends:
  outside UART mode pin 7 carries Mega Drive pad scans that a synth could take
  for MIDI.
- `.golem status` could say "session in use" when it was free.
- In VGA 1–6 (`REG 17`) the Next runs from a faster clock (up to 33 MHz in
  VGA 6) and `.golem play`, `.golem note` and `.gsq` played faster, up to 18 %.
  They now read the video timing and keep real milliseconds in all of them.
  HDMI and VGA 0 were already right. *[checked in the simulator; pending a
  check on a VGA monitor]*

### Changed

- Shorter messages (`MT32`, `FS`, `Accel.`…), the same on screen.

### Documentation

- User guide: listen through HDMI; the Next's minijack crackles on quiet
  sounds (it is the Next's converter); TV game mode against keyboard delay;
  keyboards fixed on channel 1 and `.golem set channels alt`; which channel
  a USB keyboard should use.
- Programmer's guide: quick start for Golem music in a game.

### Known issues

- A faint click can be heard when a game or `play` resets the MT-32 while the
  reverb of the previous music is still sounding (the Golem cuts that tail
  at once). Planned for 1.2.1.
- With the Next's sound through the Pi (firmware `next_input`, experimental),
  nothing of the Next reaches the Pi after a reset until a `.golem` command:
  put `.golem status` in the autoexec.
- Clicks that only come and go, louder with `loud on`, are a loose contact on
  the Golem cable: moving it makes them (the Pi's own output was captured
  clean while they were heard).

### Tested

On hardware, 18 and 21 October 2026, by Javier: ZX Spectrum Next through
HDMI to a TV, Golem on a Raspberry Pi 4, firmware golem-1.2.0, a USB MIDI
keyboard on the Pi.

- `play` with the synth reset, `.golem usb`, the Pi's audio after a program,
  `.golem set` (volume, fx, channels alt with Monkey Island, thru, keys,
  loud), `.golem save`, the help and `GOLEM.GDE`, built with SNasm.
- `.golem note` and `play` timing through HDMI; `.midimon` with the keyboard.
- OPL3: songs on banks 72, 58 and others with the Nuked emulator, stopping
  with SPACE at many moments (nothing left sounding), `.golem bank` with the
  built-in banks and a WOPL file, `.golem status` with the bank.
- `loud`: level measured on the Next (`REG 44`), gain 4.0 chosen by ear with
  a game's MT-32 music against its PCM effects; MT-32 + PCM + AY together
  through HDMI.
- Not checked on hardware: VGA modes (no monitor at hand), a Pi 3, the
  ZX Basic MIDI monitor, pitch bend and the modulation wheel.

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
