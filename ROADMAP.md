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

## Next: 1.1

- **MIDI out through the joystick port**, for any MIDI synthesiser without a
  Pi: output selection in the driver, a cable diagram for the 3.3 V output, and
  a test with a real synthesiser.
- **Official driver ID** from the NextZXOS maintainers, replacing the
  experimental `$2D`.
- **Golem side on the analyser:** its UART replies and the I²S stream, and the
  same tests on a Raspberry Pi 4.
- **Stress tests on hardware:** large SysEx dumps, dense tracks, slow SD cards,
  a Pi that is off or restarts, driver reinstalls.

## Known issues

- A note held by the Golem when the Next is switched off can sound again later;
  no MIDI message clears it, only restarting the Pi.
- The first note of a song leaves a fixed 2 ms (50 Hz) or 11 ms (60 Hz) late;
  the rest of the song keeps exact intervals from it.

## Later

- **Interactive music for games**, in the spirit of iMUSE: jumps between
  sections at musical points, layers and transitions. The GSEQ format already
  reserves its records, so 1.0 files stay valid.
- **The driver holds MIDI while the Golem switches engine** and reports
  receive errors to the caller.
- **A cooperative player for `.MID` files** inside games, for music that is not
  converted to GSEQ.
