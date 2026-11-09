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

*Joystick port:* `.golem output left` or `right` sends MIDI out of pin 7 of
that port, for an external MIDI synth without a Pi. The signal is 3.3 V and
the cable and its diagram are not ready: do not wire a MIDI DIN cable to the
joystick port yourself. `.golem output left` sets the port up at once, at
rest, and it stays so until `.golem output golem` or power-off: while MIDI goes
out of a joystick port, that port cannot be used for a joystick (use the other
one). If the MIDI adapter stays plugged in, put `.golem output left` in the
autoexec: without it, from power-on the Next uses that pin to read Mega Drive
pads and the synth gets short pulses that some synths could take for data.

*Where you hear it:* the Golem's sound reaches the Next in digital form and the
Next mixes it with its own (AY, beeper…). It comes out of both its outputs:

- **HDMI (recommended):** the mix goes digitally to the TV or amplifier, which
  converts it well. It sounds clean.
- **The Next's minijack:** the Next itself converts to analogue with a very
  simple converter. Quiet sounds (a note fading out, reverb) crackle, and the
  crackle changes with the note. It is the Next, not the Golem: the original
  mt32-pi firmware does the same.
- **When playing a keyboard,** the TV usually delays the sound (50 to 150 ms)
  to keep it in sync with the picture. Turn on the TV's **game mode** for the
  Next's input.

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
5. **What you select with `.golem` is not saved.** The engine, ROM set and
   SoundFont you change from the Next last until the Pi is switched off or
   restarts; it then goes back to `mt32-pi.cfg`: `default_synth` in `[system]`
   (`mt32` or `soundfont`), `rom_set` in `[mt32emu]` (`old`, `new`, `cm32l` or
   `any`) and `soundfont` in `[fluidsynth]` (the number). Change those values
   for other defaults. The engine does not matter if you use `.mt32` or `.gm`,
   which select it every time.

## 4. Installing on the Next

1. Copy `GOLEM.DRV` to `c:/nextzxos/`, the commands `GOLEM`, `MT32`, `GM`,
   `GSQ` and `MIDIMON` to `c:/dot/`, and the help `GOLEM.GDE` (package `docs/guides` folder)
   to `c:/docs/guides/`. `.guide golem` then shows it on the Next.
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
| `.golem play file.mid [bank]` | Plays a MIDI file (SMF 0 or 1, up to 24 tracks and 1 MB). SPACE cancels. A number after the file first chooses the OPL3 bank, as `.golem bank` does: `.opl3 play doom.mid 72`. |
| `.golem note <note> <vel> <sec> [channel]` | Plays a test note: note 0–127, velocity 1–127, 1–60 seconds, channel 1–16 (1 if omitted). With the MT-32 engine use channels 2–10: channel 1 is silent. |
| `.golem status` | Checks the driver and asks the Golem for its engine, ROM set and SoundFont, e.g. "Golem: engine MT32; ROM new; SoundFont 0"; with the OPL3 engine also its bank ("engine OPL3; bank 72; …"). Without an answer within 0.2 s it says "no answer". "RX errors" means bytes were received with errors. |
| `.golem engine mt32` / `fluidsynth` / `opl3` | Switches the Pi's engine: MT-32 (Munt), General MIDI (FluidSynth) or General MIDI with OPL3 FM synthesis, the sound of a Sound Blaster 16 (libADLMIDI; firmware golem-1.2.0). |
| `.golem soundfont <0-127>` | Selects the FluidSynth SoundFont by number. |
| `.golem bank <0-127>` | Instrument bank of the OPL3 engine (72, DMXOPL3, at start-up). 0–78 are built in; some to try: 0 The Fat Man (AIL), 58 and 59 The Fat Man for Windows 9x (2 and 4 operators), 72 DMXOPL3. Your own banks: WOPL files (made or converted with OPL3 Bank Editor) in the `opl3` folder of the Pi's SD card, numbered from 79 in alphabetical order. Changing the bank stops the notes and resets the instruments. Firmware golem-1.2.0. |
| `.golem rom old` / `new` / `cm32l` | Selects the ROMs: old MT-32, new MT-32 or CM-32L. |
| `.golem output golem` / `left` / `right` | Chooses where MIDI goes: the Golem (Accelerator header, the default) or pin 7 of the left or right joystick port, for an external synth. Without a word it reports the current one. |
| `.golem usb off` / `on` / `bridge` | Forwarding to USB MIDI devices attached to the Pi (a USB-DIN interface, another synth). `on`: the Golem plays and so does the USB device; `bridge`: only USB, the Golem stays silent; `off`: only the Golem. Without a word it reports the mode and how many USB MIDI devices are attached. Needs firmware golem-1.1.0 or later; an older one gives "firmware too old". |
| `.golem set volume <0-100>` | Master volume of both engines (100 at start-up); the same one a Pi HAT's buttons or encoder change. |
| `.golem set fx on` / `off` | FluidSynth reverb and chorus on every channel. `off` gives a dry sound for playing a keyboard. |
| `.golem set channels std` / `alt` | MT-32 channels: `std` parts on 2–10, as a real MT-32; `alt` 1–8 with rhythm on 10, for keyboards fixed on channel 1. |
| `.golem set thru on` / `off` | A USB keyboard on the Pi also plays the USB MIDI devices (see `usb`). |
| `.golem set keys on` / `off` | A USB keyboard on the Pi also sends what is played to the Next, for programs that read MIDI (the Golem plays it as well). |
| `.golem set loud on` / `off` | Makes the Golem louder without distortion (a limiter holds the peaks). Through HDMI the Golem can only be half as loud as the Next's PCM sound; this evens a game's music and effects out. Very quiet passages come up a little too. Firmware golem-1.2.0. |
| `.golem save` / `save clear` | Keeps the Golem's current settings (engine, ROM set, SoundFont, `set` and `usb`) for its next start, in `golem.cfg` next to `mt32-pi.cfg` on the Pi's SD card, which it reads after `mt32-pi.cfg`. `clear` deletes that file. |
| `.golem reset` | Returns the synth to its factory state: sends the MT-32 reset and GM System On. Clears what earlier songs' SysEx loaded (instruments, rhythm, effects). |

- `.mt32`, `.gm` and `.opl3` take the same orders. Before `play` and `note`
  they ask the Pi for the MT-32, the FluidSynth or the OPL3 engine and wait until it is ready; if
  it already is, nothing changes. If nothing answers within 0.2 seconds (an
  external MIDI synth, for example), they play anyway. `.golem` leaves the
  engine as it is. For example, `.gm play song.mid` for a General MIDI file
  and `.mt32 play game.mid` for an MT-32 one.
- `play` resets the synth before each song, like `.golem reset`, so the
  previous song's SysEx does not carry over (a song that needs its own
  instruments sends them itself). `note` does not reset.
- Before each song, `play` cleans the synthesiser: releases the sustain
  pedal, stops the notes and sets every channel's volume to 100. When the song
  ends or is cancelled it stops all notes again.
- A MIDI keyboard on the Pi's USB (directly or through a USB-MIDI
  interface) plays the Golem's synth alongside the Next. It is heard from the
  first Golem command that uses the driver (`play`, `note`, `output`); to
  hear it from power-on, put `.golem output golem` in the autoexec. Both share the 16
  channels: if the keyboard uses a channel the song also uses they mix, and
  the song's cleanup at the end also stops the keyboard's notes. With the
  FluidSynth engine (General MIDI) set the keyboard to channel 16, the one GM
  songs use least; 10 is percussion. With the MT-32 engine only channels
  2–10 sound (1 and 11–16 are silent) and an MT-32 song usually uses all of
  them: play on one that song does not use, or with the Next stopped.
- Many simple keyboards cannot change channel and always play on channel
  **1**. FluidSynth plays it; the MT-32 does not. To play it with the MT-32:
  `.golem set channels alt` (part 1 moves to channel 1), and `std` again for
  MT-32 games and songs, which expect channel 2.
- For a dry piano when playing a keyboard, without reverb or chorus
  (FluidSynth): `.golem set fx off`; `on` brings them back. If an instrument
  still has chorus, it comes from the SoundFont itself: `chorus = off` in
  `mt32-pi.cfg`. For other programs and players there are also `DRY.MID` and
  `EFFECTS.MID` (package `midi` folder), but their effect lasts only until the
  next `play`.
- The `set` settings survive `play`, `reset` and the reset SysEx songs send,
  and last until the Pi is switched off (or longer with `.golem save`). At start-up the volume is 100 and the
  rest come from `mt32-pi.cfg` (`reverb`/`chorus`, `midi_channels`,
  `usb_in_thru`). A song can still change the MT-32 volume itself. Without a
  value, `set` only reports: `.golem set volume` → "Golem: volume 80". It
  needs firmware golem-1.1.0 or later.
- `.golem` alone shows a one-line summary of the commands; the full help is
  `.guide golem`.
- `engine`, `soundfont` and `rom` wait for the Pi to confirm the change, for
  up to about 30 seconds, because loading a SoundFont takes time. SPACE ends
  the wait, but the Pi may still apply the change.
- `soundfont` also works with the MT-32 engine selected: it prepares that
  SoundFont, which you will hear after `engine fluidsynth`. It fails if there
  is no SoundFont with that number, none on the SD card, or it cannot load.
- **Do not play music while the Pi is switching SoundFonts:** while loading it
  does not serve the port and could lose data.
- `output` applies to everything that uses the driver (`.golem`, `.gsq` and
  games) until the driver is uninstalled or the Next restarts; to keep it, put
  it in the autoexec after `.install`. While the output is a joystick port, that
  port does not work as a joystick (the other one does), music or not. With a joystick
  output, `.mt32` and `.gm` do not ask the Golem and play straight away.
- Errors are returned to BASIC as normal error reports (for example
  "Golem: GOLEM.DRV missing or incompat."), so they can
  be handled with `ON ERROR`.

### `.gsq`

```
.gsq music.gsq
```

Plays a GSEQ file. **P** pauses and resumes; **SPACE** stops. Pausing really
silences the MT-32, and resuming plays again the notes that were sounding.

### `.midimon`

```
.midimon
```

Shows every MIDI message that reaches the Next, in hexadecimal, one per line
(`90 3C 64` is a note on), until SPACE is pressed. To see a USB keyboard on
the Golem, first `.golem set keys on`; for a DIN keyboard on the joystick
adapter's MIDI IN, `.golem output left` (or `right`). The Golem's own replies
are not shown. Useful to check a keyboard, its channel and its controllers.

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

For programmers: how to use the driver and the GSEQ library from BASIC,
ZX Basic or assembler is in the
[programmer's guide](../programming.md). The format and library design are in
[`m6-gseq.md`](../m6-gseq.md) (in Spanish).

## 7. Troubleshooting

| Symptom | What to check |
| --- | --- |
| Crackle on note tails or reverb, only from the Next's minijack | It is the Next's analogue converter. Listen through HDMI. |
| When playing a keyboard, the sound comes late through the TV | TV delay: turn on its game mode for the Next's input. |
| The keyboard does not sound with the MT-32 but does with FluidSynth | The keyboard plays on channel 1, which the MT-32 does not use: `.golem set channels alt` (section 5). |
| "Golem: GOLEM.DRV missing or incompat." | The driver is not installed (`.install`, section 4). |
| No sound at all | `output_device = i2s` in `mt32-pi.cfg`; the Pi's power supply (a blinking red LED means it is too weak); cable and shared ground. |
| Sound, but not MT-32 instruments, or SysEx has no effect | The ROMs did not load and the Pi is on FluidSynth: check they are complete and only one control ROM per variant. Try `.golem engine mt32`, or play with `.mt32 play`. |
| A song sounds with odd instruments after another one, but fine on its own | The previous song loaded SysEx (its own instruments) and they are still in the synth. `play` already resets the synth; when playing from another program, run `.golem reset` first. |
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
