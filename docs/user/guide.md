# golem-next: user guide

*Version 1.0.0, 8 October 2026. Versión en español:
[guia.md](guia.md).*

golem-next lets the ZX Spectrum Next play MIDI music with Roland MT-32 or
General MIDI quality. The Next sends MIDI through its serial port to a
Raspberry Pi running the **Golem** firmware (based on mt32-pi), which makes
the sound with **Munt** (MT-32 / CM-32L emulation) or **FluidSynth** (General
MIDI SoundFonts) and sends it back to the Next over I²S. The audio comes out of
the Next: HDMI or the analogue output.

What goes on the Next:

- **`GOLEM.DRV`**, the NextZXOS driver that talks to the Pi. Every program uses
  it.
- **`.GOLEM`**: plays MIDI files, plays test notes and changes the
  synthesiser settings. **`.MT32`** and **`.GM`** are the same command, but
  before playing they put the Pi in MT-32 or General MIDI mode.
- **`.GSQ`**: plays GSEQ files (`.GSQ`), the precompiled music format used by
  games.

## 1. What you need

- A ZX Spectrum Next with NextZXOS.
- A Raspberry Pi with the Golem firmware: the **Golem Sound Module** from
  Golem Retro, or your own Pi 3 or Pi 4 with a suitable cable. This version
  was tested with a Pi 3.
- **A separate power supply for the Pi.** The Pi is not powered by the Next.
  With a weak supply it receives no MIDI and its red LED blinks.
- **For MT-32 sound:** the MT-32 or CM-32L ROMs, which are not included and
  must be supplied by you. Without them only FluidSynth is available.
- **For General MIDI:** at least one SoundFont (`.sf2` or `.sf3`).

## 2. Connection

The Golem Sound Module comes ready to use. If you build your own cable, read
this before connecting anything:

- **Power supplies stay separate.** Isolate every 5 V and 3.3 V line between
  the Next and the Pi (on the Pi: pins 2 and 4 for 5 V, 1 and 17 for 3.3 V).
  Only ground (GND) is shared.
- The link uses the Next's **Accelerator header**, which is not J15. It
  carries the UART (MIDI to the Pi) and I²S (audio back).
- Do not plug in a full 40-way ribbon without checking orientation and that
  the power lines are isolated.
- **Never connect or disconnect with the equipment switched on.**
- Signals are 3.3 V. This is not an RS-232 port or a MIDI DIN input.

Pi-side pins (Pi 40-pin numbering):

| Signal | GPIO | Pin |
| --- | --- | --- |
| Pi RX (MIDI from the Next) | GPIO15 | 10 |
| Pi TX (Golem replies) | GPIO14 | 8 |
| BCLK (I²S) | GPIO18 | 12 |
| LRCLK (I²S) | GPIO19 | 35 |
| Audio data to the Next | GPIO21 | 40 |
| Ground | — | 6 (or any GND) |
| 5 V and 3.3 V | — | 2, 4, 1, 17: **isolated, not connected** |

*For a 1.x version:* MIDI output through the joystick port, to drive an
external MIDI synth without a Pi. The Next already sends MIDI there,
at 3.3 V, but the cable and its diagram are not ready: do not wire a MIDI DIN
cable to the joystick port yourself.

## 3. Preparing the Pi

1. Download the Golem firmware release from github.com/malandante/mt32-pi/releases
   and copy its contents to a blank FAT32 SD card. The firmware source code
   (GPL-3.0) is in the same repository.
2. In `mt32-pi.cfg`, **change only these values** and leave the rest alone:

   ```ini
   [midi]
   gpio_baud_rate = 31250
   gpio_thru = off

   [audio]
   output_device = i2s
   sample_rate = 48000
   ```

   Without `output_device = i2s` the sound does not reach the Next.
3. **MT-32 ROMs** in the `roms/` folder: complete ROMs only (for example
   `mt32_ctrl_1_07.rom` and `mt32_pcm.rom`, or `cm32l_ctrl_1_02.rom` and
   `cm32l_pcm.rom`), and a single control ROM per variant. Split ROMs
   (`_a`/`_b`, `_h`/`_l`) can stop the MT-32 from starting; mt32-pi then
   falls back to FluidSynth without telling you.
4. **SoundFonts** in `soundfonts/`. They are numbered in alphabetical order,
   so give them a fixed prefix: `000-GeneralUser.sf2`, `001-…`.

## 4. Installing on the Next

1. Copy `GOLEM.DRV` to `c:/nextzxos/` and the commands `GOLEM`, `MT32`, `GM` and
   `GSQ` to `c:/dot/`.
2. Install the driver:

   ```
   .install "c:/nextzxos/GOLEM.DRV"
   ```

3. To avoid installing it every time, add it to the start-up program
   `c:/nextzxos/autoexec.bas`. If it does not exist, type the line below in
   NextBASIC and store it with `SAVE "c:/nextzxos/autoexec.bas"`. If it does,
   load it, add the line and save it the same way:

   ```
   10 .install "c:/nextzxos/GOLEM.DRV"
   ```

4. To remove it: `.uninstall "c:/nextzxos/GOLEM.DRV"`.

The driver enables the Pi's I²S audio input by itself while a program uses it,
and puts it back as it was afterwards. It uses the experimental driver ID
`$2D`; an official one will be requested from the NextZXOS maintainers.

## 5. Commands

### `.golem`, `.mt32` and `.gm`

| Command | What it does |
| --- | --- |
| `.golem play file.mid` | Plays a MIDI file (SMF 0 or 1, up to 24 tracks and 1 MB). SPACE cancels. |
| `.golem note <note> <vel> <sec> [channel]` | Plays a test note: note 0–127, velocity 1–127, 1–60 seconds, channel 1–16 (1 if omitted). |
| `.golem status` | Checks the driver and asks the Golem for its engine, ROM set and SoundFont, e.g. "Golem: engine MT-32; ROM new; SoundFont 0". Without an answer within 0.2 s it says "no answer". |
| `.golem engine mt32` / `fluidsynth` | Switches the Pi's engine: MT-32 (Munt) or General MIDI (FluidSynth). |
| `.golem soundfont <0-127>` | Selects the FluidSynth SoundFont by number. |
| `.golem rom old` / `new` / `cm32l` | Selects the ROMs: old MT-32, new MT-32 or CM-32L. |

- `.mt32` and `.gm` take the same orders. Before `play` and `note` they ask
  the Pi for the MT-32 or the FluidSynth engine and wait until it is ready; if
  it already is, nothing changes. If nothing answers within 0.2 seconds (an
  external MIDI synth, for example), they play anyway. `.golem` leaves the
  engine as it is. For example, `.gm play song.mid` for a General MIDI file
  and `.mt32 play game.mid` for an MT-32 one.
- Before each song, `play` cleans the synthesiser: releases the sustain
  pedal, stops the notes and sets every channel's volume to 100. When the song
  ends or is cancelled it stops all notes again.
- `engine`, `soundfont` and `rom` wait for the Pi to confirm the change, for
  up to about 30 seconds, because loading a SoundFont takes time. SPACE ends
  the wait, but the Pi may still apply the change.
- `soundfont` also works with the MT-32 engine selected: it prepares that
  SoundFont, which you will hear after `engine fluidsynth`. It fails if there
  is no SoundFont with that number, none on the SD card, or it cannot load.
- **Do not play music while the Pi is switching SoundFonts:** while loading it
  does not serve the port and could lose data.
- Errors are returned to BASIC as normal error reports (for example
  "Golem: GOLEM.DRV missing or incompatible"), so they can
  be handled with `ON ERROR`.

### `.gsq`

```
.gsq music.gsq
```

Plays a GSEQ file. **P** pauses and resumes; **SPACE** stops. Pausing really
silences the MT-32, and resuming plays again the notes that were sounding.

## 6. Converting music to GSEQ

Games use GSEQ: MIDI music converted on the PC into a format the Next plays
with very little work. The converter is `tools/host/gseq.py` and needs
Python 3:

```
python tools/host/gseq.py music.mid -o MUSIC.GSQ
python tools/host/gseq.py theme.mid -o THEME.GSQ --loop
python tools/host/gseq.py theme.mid -o THEME.GSQ --loop-start-ms 4000 --report report.json
```

- `--loop` repeats the whole song; `--loop-start-ms N` jumps back to
  millisecond N. If the MIDI has `loopStart` and `loopEnd` markers, those are
  used.
- `--sysex-gap N` leaves N ms after each SysEx before the next messages.
  Needed with a real MT-32, not with mt32-pi.
- `--target mt32|gm` records which synthesiser the music is for.
- The converter warns when a passage needs more than the cable can carry
  (3125 bytes per second) or when notes are left sounding at the loop point.

For programmers: the playback library (`src/lib/gseq.s`, with a ZX Basic
binding in `src/lib/gseq.bas`) is described in
[`docs/m6-gseq.md`](../m6-gseq.md) (in Spanish).

## 7. Troubleshooting

| Symptom | What to check |
| --- | --- |
| "Golem: GOLEM.DRV missing or incompatible" | The driver is not installed (`.install`, section 4). |
| No sound at all | `output_device = i2s` in `mt32-pi.cfg`; the Pi's power supply (a blinking red LED means it is too weak); cable and shared ground. |
| Sound, but not MT-32 instruments, or SysEx has no effect | The ROMs did not load and the Pi is on FluidSynth: check they are complete and only one control ROM per variant. Try `.golem engine mt32`, or play with `.mt32 play`. |
| A PC game's music takes long to start | Many Sierra and other soundtracks start with several seconds of SysEx and silence. Loading the file itself takes a couple of seconds. |
| In other programs, pausing leaves notes hanging | The 1987 MT-32 ignores "All Sound Off" (CC120). `.gsq` and the GSEQ library pause by lowering the volume and releasing the notes. |
| After switching the Next off mid-note, that note sounds again when the next music loads | The Pi has its own power and keeps that sound; no MIDI message clears it. Stop programs before switching off, or restart the Pi. |
| `engine` or `soundfont` end with "Golem: transport error or timeout" | The Pi did not answer: check it runs the Golem firmware (not the original mt32-pi) and the Pi TX line in the cable. |

## 8. Licences

- **golem-next** (driver, commands, library and tools): MIT licence. You can
  use it in commercial or closed programs as long as you keep the copyright
  notice.
- **Golem firmware:** GPL-3.0, like mt32-pi, which it derives from. Its source
  code is at github.com/malandante/mt32-pi.
- No Roland ROMs or commercial music are included.

Copyright (c) 2026 Javier Aguilar Saavedra (malandante), Golem Retro.
