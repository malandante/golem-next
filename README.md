# golem-next

MIDI driver, dot commands and music libraries for the **ZX Spectrum Next**.

The Next sends MIDI over its UART to a **Golem**: a Raspberry Pi 3 or 4,
outside the Next, running the Golem firmware (based on mt32-pi). The Golem
plays it with one of three engines and sends the audio back to the Next over
I²S, so it comes out of the Next's own outputs:

- **MT-32 / CM-32L** (Munt), for the Roland soundtracks of the PC classics;
- **General MIDI** (FluidSynth, with any SoundFont);
- **OPL3** (libADLMIDI with Nuked OPL3), the AdLib / Sound Blaster FM sound,
  with 79 banks and your own.

## What is in it

- **`GOLEM.DRV`**: a NextZXOS driver any program can call (`M_DRVAPI`): MIDI
  out and in, and the Golem's replies.
- **`.GOLEM`**: plays MIDI files and test notes, chooses the engine, ROM set,
  SoundFont and OPL3 bank, and shows the Golem's status. **`.MT32`**, **`.GM`**
  and **`.OPL3`** do the same, switching the Golem to that engine first.
- **`.GSQ`** and the **GSEQ library**: precompiled music for games, with
  loops, pause and sound effects, from assembler or ZX Basic.
- **`.GPARAM`** and the **`gp_*` library**: read and change what the Golem
  plays: OPL3 instruments and banks, the MT-32's memory, FluidSynth's effects,
  engine settings.
- **`.MIDIMON`** and the **MIDI input library**: a MIDI keyboard on the Next.
- **PC tools** (Python 3): `gseq.py` (MIDI to GSEQ) and `golembank.py` (OPL3
  banks and `.SBI` instruments).
- **MIDI out through a joystick port**, to a real MT-32 or any MIDI synth,
  without a Golem.

## Get started

- **Download:** the SD package (`golem-next-<version>.zip`, with
  `SHA256SUMS`) is on the [releases page](https://github.com/malandante/golem-next/releases).
  The Golem firmware and its source are at
  [malandante/mt32-pi](https://github.com/malandante/mt32-pi/releases).
- **Quick start** (the cable, the cards, the first sound):
  [English](docs/user/quickstart.md) · [español](docs/user/inicio-rapido.md).
- **User guide:** [English](docs/user/guide.md) · [español](docs/user/guia.md).
- **Programmer's guide:** [music and MIDI in your own programs](docs/programming.md)
  (BASIC, ZX Basic, assembler).
- **Release notes:** [RELEASE_NOTES.md](RELEASE_NOTES.md) · **Roadmap:**
  [what has been done and what comes next](ROADMAP.md).

## Hardware

Today the Golem is connected with a 40-wire ribbon cable with four wires cut,
as the quick start explains. **The Pi has its own power supply: never join the
Next's and the Pi's 5 V or 3.3 V lines, only ground.**

The **Golem Link** is on its way: a board the size of the Next's Pi Zero, with
a mini HDMI connector in the same place, and a mini HDMI cable out to the Pi.
The v0.1 prototypes are being tested. Its connector is **not HDMI**: never
plug it into a TV or monitor.

## Developer documentation

The specifications below are in Spanish for now; English versions are on the
way.

- [Driver ABI](docs/driver-api.md) and its [changelog](ABI_CHANGELOG.md)
- [Sound-parameter protocol](docs/sound-params.md) (`.GPARAM`, `gp_*`)
- [GSEQ format and library](docs/m6-gseq.md)
- [The Golem's control protocol](docs/mt32-pi-control.md) and
  [its minimal architecture](docs/golem-architecture.md)
- [Architecture and NextZXOS analysis](docs/architecture.md)
- [MIDI through a joystick port](hardware/joystick-midi/README.md)
- [Licensing and third-party code](docs/licensing.md)
- [CSpect → Munt test bench](tests/integration/cspect/README.md) ·
  [hardware tests](tests/hardware/README.md) ·
  [recordable Monkey Island demo](tests/demo/mi1/README.md)

## Building

With NextBuild 10 in its default location (Windows, PowerShell):

```powershell
& .\tools\build-driver.ps1
& .\tools\build-golem.ps1
& .\tools\build-gseq-bank.ps1
& .\tools\build-gparam-bank.ps1
& "$env:USERPROFILE\Documents\NextBuildv10\Python\python.exe" `
  -m unittest discover -s .\tests\host -v
```

The SD package with its hashes (the same one CI publishes for each release):

```powershell
& "$env:USERPROFILE\Documents\NextBuildv10\Python\python.exe" `
  .\tools\release\build_release.py --assembler snasm `
  --assembler-path "$env:USERPROFILE\Documents\NextBuildv10\Emu\CSpect\SNasm.exe" `
  --out C:\temp\golem-dist
```

It leaves `C:\temp\golem-dist\golem-next-<version>\` and the `.zip`; its
`SHA256SUMS` must match the release's (built with sjasmplus).

The driver is built as `build/GOLEM.DRV` and the commands as `build/GOLEM`,
`build/MT32`, `build/GM` and `build/OPL3` (the same code; `CLI_ENGINE` in
`src/dot/golem_cli.s`), with `build/MIDIMON` and `build/GPARAM`. The test clients (`MTTEST`, `MTSTRESS`, `MTAPIERR`,
`MTNOID`, `MTCOLLIDE`, `MTSTATE`, `MTDURATION`) are experimental. The driver
uses the experimental ID `$2D` until NextZXOS assigns one.

## License

golem-next is MIT licensed ([LICENSE](LICENSE)): anyone may use the driver,
the commands, the libraries and the specifications, also in closed or
commercial games, keeping the copyright notice. The Golem firmware is a
separate program under GPL-3.0, inherited from mt32-pi. No Roland ROMs,
commercial music or other projects' code are included. Details:
[docs/licensing.md](docs/licensing.md).
