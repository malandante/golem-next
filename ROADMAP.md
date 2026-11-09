# golem-next roadmap

Each milestone closes with something that can be checked: a test suite, a
capture or a measurement on real hardware. The evidence is in this repository.

## Done

| Date | Milestone | Evidence |
| --- | --- | --- |
| 2026-09-30 | **Architecture.** NextZXOS driver model, transport over the Next UART, audio back over I²S, and a CSpect + Munt test bench before touching hardware. | [`docs/architecture.md`](docs/architecture.md) |
| 2026-10-02 | **Driver and ABI** (`GOLEM.DRV`, then `MT32.DRV`): install, query, acquire/release, bounded writes, error codes, state preserved across calls. | CSpect suites at 3.5/7/14/28 MHz and 50/60 Hz, relocation check in CI ([`docs/driver-api.md`](docs/driver-api.md)) |
| 2026-10-02 | **Foreground player:** SMF 0/1, tempo maps, SysEx, cancel with cleanup, raster-based 1 ms scheduler. | Byte-exact oracles and timing matrix in CSpect ([`tests/integration/cspect/`](tests/integration/cspect/README.md)) |
| 2026-10-02 | **Real MT-32 music:** Monkey Island (17 tracks) and a King's Quest V excerpt with SysEx, played through Munt. | Local captures; commercial files are not in the repository |
| 2026-10-03 | **Golem control protocol:** a versioned, transaction-matched SysEx to switch engine, ROM set and SoundFont, with replies from the Pi. | Host tests shared with the [firmware fork](https://github.com/malandante/mt32-pi); CSpect two-way runs with stale replies, errors and timeouts |
| 2026-10-05 | **First run on hardware:** Next + Raspberry Pi 3 over UART and I²S. Driver timing measured on the Next (lines per frame, interrupts held per call) and SD loading speed. | [`tests/hardware/README.md`](tests/hardware/README.md) (`.MTFRAME`, `.MTLOAD`) |
| 2026-10-05 | **MIDI files up to 1 MB**, read through 8K banks, at 28 MHz while playing. | Large-file fixture in [`tests/fixtures/`](tests/fixtures) |
| 2026-10-06 | **GSEQ format and library:** precompiled music for games with loops, pause, stop, sound effects and a bounded cost per call, from assembler or ZX Basic. | Converter tests, Z80 harness, measured cost per call ([`docs/m6-gseq.md`](docs/m6-gseq.md)); running a full game's music on the Next |
| 2026-10-07 | **`.GOLEM`, `.MT32` and `.GM`:** one command; the aliases switch the Golem engine first and fall back to any MIDI synth; `status` asks the Golem for its state. | Z80 harness runs with and without Golem replies; checked on the Next |
| 2026-10-08 | **Analyser captures on the Next:** byte-exact output, 31250 baud, event intervals exact to 0.05 ms at 50 and 60 Hz; MIDI out through the joystick port measured at 3.3 V. | [`tests/hardware/results/2026-10-08-joystick/`](tests/hardware/results/2026-10-08-joystick/README.md) |
| 2026-10-08 | **Release 1.0.0:** reproducible SD package with SHA-256 sums; Golem firmware release with its source. | [`RELEASE_NOTES.md`](RELEASE_NOTES.md), `tools/release/build_release.py` |
| 2026-10-13 | **MIDI out through a joystick port** (`.golem output`), driver ABI 0.3 with receive errors in `STATUS`. | Analyser captures on the Next ([`tests/hardware/results/2026-10-13-joystick-output/`](tests/hardware/results/2026-10-13-joystick-output/README.md)); driver checks in a Z80 simulator in CI |
| 2026-10-13 | **Release 1.1.0.** | [`RELEASE_NOTES.md`](RELEASE_NOTES.md) |
| 2026-10-21 | **Release 1.2.0: an OPL3 engine** (libADLMIDI, Nuked OPL3) next to MT-32 and General MIDI, with 79 banks and your own WOPL files; USB MIDI through the Golem, settings kept by the firmware, MIDI input for programs, a limiter for louder music. | [`RELEASE_NOTES.md`](RELEASE_NOTES.md); checked on a Next with a Raspberry Pi 4 |
| 2026-11-09 | **Release 1.3.0: sound parameters.** One protocol to read and change what the Golem plays: OPL3 instruments and banks, the MT-32's memory and dumps, FluidSynth's effects, engine settings. `.gparam` and the `gp_*` library. | [`docs/sound-params.md`](docs/sound-params.md), host tests shared with the firmware; checked on a Next with a Raspberry Pi 4 |

## Next

- **The Golem link:** an adapter board in the place of the Next's Pi Zero and
  one cable to the Pi, carrying the UART, the I²S audio and SPI.
- **All the Next's sound through the Golem** for VGA users: the Next's mixer
  sent to the Pi and out of its audio jack (experimental in 1.2.0).
- **OPL3 registers from games:** a game writes the chip directly, as on a PC
  with a Sound Blaster, through the sound-parameter protocol.
- **MIDI out through a joystick port to a real synthesiser:** a diagram for
  the 3.3 V signal and a test with a real MT-32.
- **Official driver ID** from the NextZXOS maintainers, replacing the
  experimental `$2D`.
- **Pause in `.golem play`** (P), as in `.GSQ`.
- **Stress tests on hardware:** large SysEx dumps, dense tracks, slow SD cards,
  a Pi that is off or restarts, driver reinstalls.

## After that: interactive music for games

How it is played, in the spirit of iMUSE: GSEQ songs with sections and markers,
and a game that asks for a change of music lands it on a musical point, with
jumps, layers and transitions. The GSEQ format already reserves its records, so
1.0 files stay valid.

## Known issues

- A note held by the Golem when the Next is switched off can sound again later;
  no MIDI message clears it, only restarting the Pi.
- The first note of a song leaves a fixed 2 ms (50 Hz) or 11 ms (60 Hz) late;
  the rest of the song keeps exact intervals from it.

## Later

- **A cooperative player for `.MID` files** inside games, for music that is not
  converted to GSEQ.
- **MIDI out to real synthesisers through the Golem:** the firmware forwards
  what the Next sends to a USB-MIDI interface on the Pi, so a hardware MT-32 or
  SC-55 can play along.
- **Hardware flow control** (RTS/CTS) on the link, for faster transfers to the
  Pi.
- **NextPi and the Golem on the same Pi**, chosen by swapping the SD card or by
  a button at boot.
