# golem-next programmer's guide

How to put MIDI music and sound into your own Next program: from a BASIC
program, from ZX Basic (Boriel / NextBuild) or from assembler. The user guide
([`user/guide.md`](user/guide.md)) covers installing the driver and the Pi; this
guide assumes `GOLEM.DRV` is installed.

There are three levels; pick the one that fits:

| Level | What you use | Good for |
| --- | --- | --- |
| 1. Dot commands | `.golem play`, `.golem note`, `.golem engine` … from BASIC | Menus, jukeboxes, loaders, intros. The command takes over until the song ends. |
| 2. GSEQ library | `GSEQ*.BIN` bank + `gseq.bas` (ZX Basic), or `gseq.s` (assembler) | Games: music that plays while the game runs, with loops, pause, song changes and sound effects. |
| 3. The driver directly | `M_DRVAPI` calls to `GOLEM.DRV` | Your own MIDI: real-time notes, your own sequencer, SysEx. |

All of them are MIT licensed: you can ship them inside closed or commercial
programs if you keep the copyright notice (`LICENSE`).

## 1. Dot commands from BASIC

```basic
10 .install "c:/nextzxos/GOLEM.DRV"
20 .golem rom new
30 .mt32 play "c:/music/intro.mid"
40 .gm play "c:/music/level1.mid"
```

- `.mt32` and `.gm` switch the Golem to MT-32 or General MIDI first;
  `.golem` leaves the engine as it is. With an external MIDI synth instead of a
  Golem they play anyway.
- Every error is a normal NextZXOS error report, so `ON ERROR` works.
- `play` returns when the song ends or when the user presses SPACE.
- Engine, ROM set and SoundFont changes are not saved on the Pi: set them at
  the start of your program if you need them.
- Each `play` prints three lines. A jukebox that plays many songs in a row
  without clearing the screen will stop at `Scroll?`; `CLS` between songs
  avoids it.

## 2. GSEQ: music in a game

### 2.1 Convert the music

GSEQ is MIDI already merged, timed in milliseconds and checked on the PC, so
the Next only compares times and copies bytes. Convert with
`gseq.py` (Python 3; `tools/gseq.py` in the SD package, `tools/host/gseq.py`
in the repository):

```
python tools/gseq.py title.mid -o TITLE.GSQ
python tools/gseq.py level1.mid -o LEVEL1.GSQ --loop --report level1.json
python tools/gseq.py boss.mid -o BOSS.GSQ --loop-start-ms 4000 --target mt32
```

- `--loop` repeats the whole song; `--loop-start-ms N` jumps back to
  millisecond N; `loopStart` / `loopEnd` markers in the MIDI file also work.
- `--target mt32|gm` records which synth the music was written for
  (`gsInfo(9)` reads it back).
- `--sysex-gap MS` adds silence after each SysEx, needed by a real MT-32,
  not by the Golem.
- Read the report: it warns about passages that need more than the cable
  carries (3125 bytes/s) and notes left sounding at the loop point.

A `.GSQ` file is loaded into 8K banks. One file may take several banks, and
several short files can share banks (each starts at an offset you choose).

### 2.2 ZX Basic step by step

You need from the package: one library bank (`lib/GSEQ4000.BIN` …
`lib/GSEQE000.BIN`) and `lib/gseq.bas`. The library is a whole 8K bank, mapped
into one MMU slot only during each call, so it costs no fixed memory.

**Choose two MMU slots:**
- the **library slot**: where the library bank is mapped during calls,
  slot 2 to 7 (NextReg `$52`–`$57`). Load the `.BIN` built for that slot:
  `GSEQ4000.BIN` for slot 2 (`$4000`), `GSEQC000.BIN` for slot 6 (`$C000`)
  and so on;
- the **data window**: where the music banks are mapped while the library
  reads them (NextReg `$50`–`$57`, not the library slot). Slot 0 or 1 are
  fine.

During each call those two slots change and are then put back, so nothing your
program needs at that moment may be in them: not the stack, not your interrupt
routine, not `gsBankTable` and not a message given to `GsSend`.

```basic
#define GS_MAX_BANKS 8                 ' optional: smaller bank table
#include "gseq.bas"

' 1. Load the library and the music into banks of your choice
LoadSDBank("GSEQ4000.BIN",0,0,0,60)    ' library: bank 60, built for slot 2
LoadSDBank("LEVEL1.GSQ",0,0,0,61)      ' music: banks 61, 62, ... as needed

' 2. Tell the binding where the library is, and set it up
GsSetLibrary(60,$52)                   ' bank 60, mapped in slot 2 ($52)
if GsInit($51,1,0)=GS_FAILED then ...  ' window in slot 1, key table on, all channels

' 3. Take the driver for the whole game
'    (DriverCall: see section 3.2; function 1 = ACQUIRE)

' 4. Open and start a song
gsBankTable(0)=2: gsBankTable(1)=61: gsBankTable(2)=62   ' count, then banks
if GsOpen(0)=GS_FAILED then ...        ' 0: the file starts at the bank start
if GsStart(NowMs())=GS_FAILED then ...

' 5. In the game loop, once per frame (or more often)
st=GsPump(NowMs(),4)
```

**The clock.** Every call that takes `now` wants a free-running millisecond
counter; only differences modulo 65536 matter. From the ROM frame counter:

```basic
function NowMs() as uinteger
    ' FRAMES (23672) counts video frames: 20 ms each at 50 Hz.
    return (peek(23672)+256*peek(23673))*20
end function
```

The product wraps at 65536 together with the counter, which is all the library
needs. At 60 Hz a frame is 50/3 ms: multiply the 24-bit `FRAMES` (23672–23674)
by 50 and divide by 3 in 32 bits. Interrupts must be on for `FRAMES` to count.
A clock of your own works the same.

**The budget.** The second parameter of `GsPump` is how many 16-byte writes the
call may make. Once per frame, 1 gives 800 bytes/s and 4 covers the whole cable.
A quiet song costs one write whatever the budget, so 4 is a good default; use
1 if a frame has no time to spare and call more often. Measured worst case with
budget 4 and the driver: about 67,000 T-states, 12 % of a 50 Hz frame at
28 MHz, and only during bursts such as long SysEx dumps.

**Pause, resume, stop:**

```basic
st=GsPause(NowMs())     ' silences the synth: volume 0, notes and sound off
st=GsResume(NowMs())    ' restores each channel's volume and re-strikes held notes
st=GsStop()             ' sustain off, notes off, volume back to 100
```

The cleanup messages go out over the next `GsPump` calls, so keep pumping. A
real MT-32 ignores "All Sound Off" (CC120), which is why pause also sets the
volume to 0.

**Changing song.** Stop, pump until nothing is pending, open the next one:

```basic
st=GsStop()
do
    st=GsPump(NowMs(),4)
    st=GsQuery()
loop while gsBusy<>0
gsBankTable(0)=1: gsBankTable(1)=70
st=GsOpen(0): st=GsStart(NowMs())
```

`GsStart` also cleans the synth before the song (notes and sustain off, volume
100), and the song clock waits until that has left.

**Sound effects.** Send any MIDI message of up to 16 bytes; it goes out in the
next pump, before the music, never in the middle of a music SysEx:

```basic
dim fx(0 to 2) as ubyte
fx(0)=$99: fx(1)=42: fx(2)=100           ' channel 10, closed hi-hat
st=GsSend(@fx(0),3)
```

If your effects use their own channels, keep those channels out of the
library's cleanups, or a pause would silence them too. The third parameter of
`GsInit` is the channels the cleanups may touch, bit n = MIDI channel n+1,
0 = all:

```basic
GsInit($51,1,$FDFF)     ' every channel but 10
```

`GsSend` returns `GS_FAILED` with `gsError=GS_ERR_STATE` while the previous
effect has not left yet; try again after the next pump.

**State and errors.** Every function returns the state (`GS_STOPPED`,
`GS_PLAYING`, `GS_PAUSED`, `GS_ENDED`, `GS_ERROR`) or `GS_FAILED` (255) with
the reason in `gsError`:

| `gsError` | Meaning |
| --- | --- |
| 1 `GS_ERR_FORMAT` | Not a GSEQ file, or the offset is past the first bank |
| 2 `GS_ERR_VERSION` | GSEQ major version not 1 |
| 3 `GS_ERR_CHECKSUM` | File damaged or incompletely loaded |
| 4 `GS_ERR_RECORD` | Malformed record found while playing |
| 5 `GS_ERR_DRIVER` | `GOLEM.DRV` returned an error (not installed, not acquired) |
| 6 `GS_ERR_STATE` | Call not valid now (pause while stopped, effect still waiting…) |
| 7 `GS_ERR_LIBRARY` | Library bank not loaded or wrong slot (checked by the binding) |

`GsQuery()` also fills `gsInfo`: state, error, last notice, loops played
(2 bytes), song time in ms (4 bytes) and target synth (0 any, 1 MT-32,
2 General MIDI); `gsBusy` is 1 while bytes or a cleanup are still pending.

**Finish.** Stop, pump until `gsBusy=0`, then release the driver
(function 5).

### 2.3 Assembler

Include `lib/gseq.s` (with `lib/mt32_api.inc`) in your program and call the
routines directly. Same rules: carry set on error with `A` = error code,
otherwise `A` = state; `IX` is kept, `IY` is never used, `AF`, `BC`, `DE`,
`HL` are not kept; the ROM must be in MMU0/1 during calls (the driver needs
it).

| Routine | Input |
| --- | --- |
| `gs_init` | `HL` = 16-byte output buffer (between `$4000` and `$FFFF`), `A` = NextReg of the data window, `DE` = 2048-byte key table or 0 |
| `gs_set_channels` | `HL` = channels the cleanups may touch (bit n = channel n+1) |
| `gs_open` | `HL` = bank table (count, then banks), `DE` = offset in the first bank |
| `gs_start` | `DE` = now (ms) |
| `gs_pump` | `DE` = now, `B` = write budget; returns the state |
| `gs_pause` / `gs_resume` | `DE` = now |
| `gs_stop` | — |
| `gs_send` | `HL` = message, `B` = length (1–16) |
| `gs_query` | returns `A` = state, `HL` = 10-byte information block; Z clear while busy |

```asm
        ld hl,out_buffer        ; 16 bytes, above $4000
        ld a,$51                ; read the music through slot 1
        ld de,key_table         ; 2048 bytes, or 0
        call gs_init
        ; acquire the driver (section 3), then:
        ld hl,bank_table        ; db 2, 61, 62
        ld de,0
        call gs_open
        jr c,error
        call read_clock_ms      ; your clock, into DE
        call gs_start
frame:  ; once per frame
        call read_clock_ms
        ld b,4
        call gs_pump
        jr c,error
```

Short of fixed memory? Use the bank instead (`GSEQ*.BIN`): map it in its slot
and `CALL` slot address + 3 × n, with n = 0 init (`A` = window NextReg, `B` =
key table on/off, `HL` = channel mask), 1 open (`HL` = bank table, `DE` =
offset), 2 start, 3 pump, 4 pause, 5 resume, 6 stop, 7 send, 8 query. The bank
holds its own buffer, bank table copy and key table, and maps the ROM in
MMU0/1 for each call itself. `"GSEQ",1,0` at slot address + 27 lets a loader
check it.

## 3. The driver directly

### 3.1 Calls

All calls go through `RST $08` / `M_DRVAPI` (`$92`) with `C` = driver ID
(`MT32_DRIVER_ID`, `$2D` until NextZXOS assigns an official one; always use the
constant) and `B` = function. Carry clear means success; carry set means error
with `A` = code (`A` = 0: function not supported or no driver).

| `B` | Function | Input | Output |
| --- | --- | --- | --- |
| 0 | QUERY | — | `BC` = `"MT"`, `DE` = ABI version (`$0002`), `HL` = capabilities (bit 0 partial write, bit 1 non-blocking read) |
| 1 | ACQUIRE | — | Exclusive use: sets the Pi UART to 31250 8N1 and turns on I²S audio from the Pi |
| 2 | WRITE | buffer, `DE` = length | `BC` = bytes taken (at most 16), `HL`/`DE` = what is left |
| 3 | STATUS | — | `BC`: bit 0 acquired, bit 1 TX full, bit 2 TX empty, bit 3 RX has data |
| 4 | DRAIN_STATUS | — | `BC` = `$FFFF` when everything has left |
| 5 | RELEASE | — | Gives the UART and I²S settings back as they were |
| 6 | READ | buffer, `DE` = room | `BC` = bytes received (at most 16) |

Errors: 1 busy (another program has it), 2 not acquired, 3 invalid parameter.

**The buffer pointer:** a dot command passes it in `HL`; a normal program or
NEX passes it in `IX` (NextZXOS hands it to the driver in `HL`). Save `IX` if
your compiler uses it.

**Rules:**
- **ROM in MMU0/1** during the call (NextRegs `$50` and `$51` = `$FF`).
- **Buffers between `$4000` and `$FFFF`**, visible during the call.
- **Never wait inside:** `WRITE` takes what fits (up to 16 bytes) and returns.
  Keep the rest and send it on the next call. Check `BC`, not just the carry.
- **Not from an interrupt routine.** NextZXOS runs driver calls with
  interrupts off, so a call that covers the frame interrupt loses it. Make your
  calls right after the interrupt, or count time with something else.
- **Release** before your program ends, so others can use the driver.

### 3.2 Examples

Assembler, a note on channel 1:

```asm
        include "mt32_api.inc"

        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_QUERY
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,no_driver
        ld c,MT32_DRIVER_ID
        ld b,MT32_FN_ACQUIRE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,busy

        ld ix,note_on           ; a NEX program: pointer in IX
        ld de,3                 ; length
send:   ld c,MT32_DRIVER_ID
        ld b,MT32_FN_WRITE
        rst $08
        db NEXTZXOS_M_DRVAPI
        jr c,failed
        ld a,d                  ; DE = bytes still to send
        or e
        jr z,sent
        add ix,bc               ; skip the BC bytes taken, send the rest
        jr send                 ; (a game would return and retry next frame)
sent:
        ; ... later, note off and RELEASE (function 5)

note_on: db $90,60,100          ; must be above $4000
```

ZX Basic, a function to call the driver without a buffer (QUERY, ACQUIRE,
STATUS, RELEASE):

```basic
function fastcall DriverCall(fn as ubyte) as ubyte
    ' returns 1 on success, 0 on error
    asm
        push ix
        ld b,a
        ld c,$2d                ; MT32_DRIVER_ID
        ld hl,0
        ld de,0
        rst $08
        db $92                  ; M_DRVAPI
        pop ix
        ld a,0
        jr c,driver_failed
        inc a
    driver_failed:
    end asm
end function

if DriverCall(0)=0 then print "GOLEM.DRV not installed": stop
if DriverCall(1)=0 then print "GOLEM.DRV in use": stop
' ... GSEQ or your own writes ...
DriverCall(5)
```

### 3.3 Talking to the Golem

The Golem answers a small SysEx protocol over the same cable: switch engine
(MT-32 / FluidSynth), ROM set and SoundFont, and report its state. Requests
and replies are in [`mt32-pi-control.md`](mt32-pi-control.md) (in Spanish;
`docs/golem-protocol.md` in the SD package). Each order is acknowledged with
`ACCEPTED` and then `READY` or `ERROR`, matched by a transaction number; read
the replies with `READ`. A SoundFont change can take seconds, and the Pi does
not listen to MIDI meanwhile: wait for `READY` before playing. The source of
`.golem` (`src/dot/golem/golem_client.s`) is a complete client.

## 4. Memory map summary

| What | Where | Note |
| --- | --- | --- |
| `GOLEM.DRV` | NextZXOS driver area | Installed with `.install`; costs your program nothing |
| GSEQ library bank | Any 8K bank, mapped in its slot (2–7) only during calls | Load the `.BIN` built for that slot |
| Music | Any 8K banks, read through the data window slot | Several songs may share banks (offset in `GsOpen`) |
| Output buffer, key table | Inside the library bank (bank version) or yours (`gseq.s`) | Key table: 2048 bytes, optional |
| Messages for the driver | `$4000`–`$FFFF` | Not in the library slot or the data window |

## 5. Common problems

| Symptom | Cause |
| --- | --- |
| `GS_ERR_LIBRARY` at `GsInit` | The library bank is not loaded, or it was built for another slot than the one given to `GsSetLibrary`. |
| `GS_ERR_CHECKSUM` at `GsOpen` | The `.GSQ` did not load completely, or the bank table lists the wrong banks. |
| `GS_ERR_DRIVER` | `GOLEM.DRV` not installed, or not acquired before `GsStart`. |
| ACQUIRE fails with "busy" | Another program, or your own earlier run, has not released the driver. Uninstall and install it again, or restart. |
| Music stops or slows during long SysEx | Budget too low or `GsPump` called too rarely: use budget 4, or call more often. |
| Pause leaves a note hanging on a real MT-32 | Not with GSEQ (it lowers the volume); check that your own code does not pause by sending only CC120. |
| A crash right after a library call | The stack, the interrupt routine or a buffer is in the library slot or the data window. |
| Notes from a previous run sound when the next song starts | The Pi keeps sounding if the Next is switched off mid-song; `GsStart` cleans the synth, but a note held across a power cut may need a Pi restart. |
