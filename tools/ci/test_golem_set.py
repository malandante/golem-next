"""Checks .golem set (firmware SET_PARAM) in a Z80 simulator.

1. parse_command accepts `set volume|fx|channels|thru|keys|bank [value]` (any case),
   setting golem_command = SET_PARAM, golem_value = parameter and
   golem_value2 = value (7F without one), and rejects near misses.
2. send_golem_control sends F0 7D 47 4C 4D 01 tt 05 pp vv F7 and accepts the
   firmware's READY (parameter, value); a READY with another parameter or
   value is ignored, except that a query accepts any value.
3. The confirmation prints "Golem: <parameter> <value>".
4. The one-line usage names every command and points to `.guide golem`.
5. `save` and `save clear` set SAVE 00/01; the other Golem control commands,
   which now share one ending, still set their command and mode, and
   `engine opl3` selects engine 2.
6. `.golem status` names the OPL3 engine and, with it active, asks for the bank.
7. `play FILE BANK` keeps the bank (0-127) for play and rejects near misses;
   before playing, select_engine sends SET_PARAM 5 with it, and nothing
   without one.

    python3 tools/ci/test_golem_set.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
from skoolkit.simulator import Simulator
from skoolkit import simutils as su

REPO = args.repo
ORG = 0x8000
CMDLINE = 0xC000
RET = 0x7000
FN_WRITE, FN_READ = 0x02, 0x06
MAX_READ = 16
CMD_SET = 9
CMD_SAVE = 10
SET_PARAM = 0x05
SAVE = 0x06
HEADER = bytes([0xF0, 0x7D, 0x47, 0x4C, 0x4D, 0x01])

with tempfile.TemporaryDirectory() as t:
    t = Path(t); shutil.copytree(REPO / "src", t / "src"); shutil.copytree(REPO / "include", t / "include")
    for f in (t / "src").rglob("*.s"):
        f.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", f.read_text()))
    f = t / "src/dot/golem_cli.s"
    f.write_text(f.read_text().replace("        org $2000", f"        org ${ORG:04x}", 1))
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "--sym=o.sym", "golem.s"],
                   cwd=t / "src/dot", check=True, capture_output=True)
    img = (t / "src/dot/o.bin").read_bytes()
    sym = {}
    for line in (t / "src/dot/o.sym").read_text().splitlines():
        m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", line)
        if m: sym[m.group(1).lower()] = int(m.group(2), 16)


class Ports:
    def read_port(self, regs, port): return 0xFF  # no key pressed
    def write_port(self, regs, port, value, t=0): pass


call_printed = []


def call(entry, mem, regs=None, replies=b""):
    """Runs entry until it returns; rst $08 driver calls are served here."""
    mem[0x0008] = 0xC9
    mem[0x0010] = 0xC9
    del call_printed[:]
    sim = Simulator(mem); sim.set_tracer(Ports())
    r = sim.registers
    for k, v in (regs or {}).items(): r[k] = v
    r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
    r[su.PC] = entry
    written, pending, steps = bytearray(), bytearray(replies), 0
    while r[su.PC] != RET:
        if r[su.PC] == 0x0010:
            call_printed.append(r[su.A])
        if r[su.PC] == 0x0008:
            sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1]
            ret += 1  # skip the M_DRVAPI byte
            mem[sp], mem[sp + 1] = ret & 255, ret >> 8
            hl = r[su.H] * 256 + r[su.L]; de = r[su.D] * 256 + r[su.E]
            if r[su.B] == FN_WRITE:
                written += bytes(mem[hl:hl + de])
                r[su.B], r[su.C] = de >> 8, de & 255
                hl += de; r[su.H], r[su.L] = hl >> 8, hl & 255; r[su.D] = r[su.E] = 0
            elif r[su.B] == FN_READ:
                n = min(de, MAX_READ, len(pending))
                mem[hl:hl + n] = list(pending[:n]); del pending[:n]
                r[su.C] = n
            r[su.F] &= ~1
        if mem[r[su.PC]] == 0x76:  # HALT: no more replies are coming
            return None, written
        sim.run()
        steps += 1
        if steps > 200000:
            raise RuntimeError("no return")
    return r[su.F] & 1, written


fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


def fresh():
    mem = [0] * 65536
    mem[ORG:ORG + len(img)] = list(img)
    return mem


def parse(line):
    mem = fresh()
    text = line.encode() + b"\r"
    mem[CMDLINE:CMDLINE + len(text)] = list(text)
    carry, _ = call(sym["parse_command"], mem, {su.H: CMDLINE >> 8, su.L: CMDLINE & 255})
    return carry, mem


# 1. Command line
for line, param, value in (("set volume 80", 0, 80), ("set volume 0", 0, 0), ("set volume 100", 0, 100),
                           ("set volume", 0, 0x7F), ("SET VOLUME  7 ", 0, 7), ("set volume 50:print", 0, 50),
                           ("set fx off", 1, 0), ("set fx on", 1, 1), ("Set FX On", 1, 1), ("set fx", 1, 0x7F),
                           ("set channels alt", 2, 1), ("set channels std", 2, 0), ("set channels", 2, 0x7F),
                           ("set thru on", 3, 1), ("set thru off", 3, 0), ("set  thru", 3, 0x7F),
                           ("set keys on", 4, 1), ("SET KEYS OFF", 4, 0), ("set keys", 4, 0x7F),
                           ("bank 72", 5, 72), ("BANK 0", 5, 0), ("bank 127", 5, 127), ("bank", 5, 0x7F), ("bank  79 ", 5, 79),
                           ("set loud on", 6, 1), ("SET LOUD OFF", 6, 0), ("set loud", 6, 0x7F)):
    carry, mem = parse(line)
    got = (carry, mem[sym["command_mode"]], mem[sym["golem_command"]], mem[sym["golem_value"]],
           mem[sym["golem_value2"]])
    check(got == (1, CMD_SET, SET_PARAM, param, value), f"'{line.strip()}' -> SET_PARAM {param} {value:02X}")

for line in ("set volume 101", "set volume 256", "set vol 80", "set volume x", "set volume 80 1",
             "set fx maybe", "set fx o", "set fx onn", "set channels alternate", "set channels 1",
             "set thru bridge", "set key on", "set keys 1", "bank on", "bank 128", "bank 300", "set bank 72", "set bank", "banks 1", "set loud 1", "set loudness on", "set banks 1", "set", "set ", "setx volume", "set gain 1", "se volume 1"):
    carry, _ = parse(line)
    check(carry == 0, f"'{line}' rejected")

carry, mem = parse("status")
check(carry == 1 and mem[sym["command_mode"]] == 2, "'status' still parses")
carry, mem = parse("soundfont 3")
check(carry == 1 and mem[sym["command_mode"]] == 4 and mem[sym["golem_value"]] == 3, "'soundfont 3' still parses")


# 2. Request and replies
def exchange(param, value, ready, tt=0x21):
    mem = fresh()
    mem[sym["golem_command"]] = SET_PARAM
    mem[sym["golem_value"]] = param
    mem[sym["golem_value2"]] = value
    mem[sym["golem_transaction"]] = tt
    accepted = HEADER + bytes([tt, 0x40, SET_PARAM, 0xF7])
    reply = HEADER + bytes([tt, 0x41, SET_PARAM, *ready, 0xF7])
    carry, written = call(sym["send_golem_control"], mem, replies=accepted + reply)
    return carry, written, (mem[sym["golem_status"]], mem[sym["golem_status"] + 1])


for param, value, ready in ((0, 80, (0, 80)), (1, 0, (1, 0)), (2, 1, (2, 1)), (3, 1, (3, 1)),
                            (0, 0x7F, (0, 64)), (1, 0x7F, (1, 1))):
    carry, written, status = exchange(param, value, ready)
    want = HEADER + bytes([0x21, SET_PARAM, param, value, 0xF7])
    check(written == want, f"request {param} {value:02X} is {written.hex(' ').upper()}")
    check(carry == 0 and status == ready, f"READY {ready} accepted")

carry, _, _ = exchange(0, 80, (0, 79))
check(carry is None, "READY with another value is ignored")
carry, _, _ = exchange(1, 0x7F, (2, 1))
check(carry is None, "READY for another parameter is ignored")

# soundfont still sends its 14-bit payload
mem = fresh()
mem[sym["golem_command"]] = 0x03
mem[sym["golem_value"]] = 5
mem[sym["golem_value2"]] = 0x55
mem[sym["golem_transaction"]] = 0x21
_, written = call(sym["send_golem_control"], mem, replies=HEADER + bytes([0x21, 0x41, 0x03, 5, 0, 0xF7]))
check(written == HEADER + bytes([0x21, 0x03, 5, 0, 0xF7]), f"soundfont request is {written.hex(' ').upper()}")


# 3. and 4. Printed text
def printed(entry, setup):
    mem = fresh()
    mem[0x0010] = 0xC9
    mem[0x0008] = 0xC9
    setup(mem)
    sim = Simulator(mem); sim.set_tracer(Ports())
    r = sim.registers
    r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
    s = sym["saved_sp"]; mem[s], mem[s + 1] = 0xEFFE & 255, 0xEFFE >> 8
    r[su.PC] = entry
    text, steps = bytearray(), 0
    while r[su.PC] != RET:
        if r[su.PC] == 0x0010:
            text.append(r[su.A])
        if r[su.PC] == 0x0008:  # driver calls during cleanup: skip the M_DRVAPI byte, no carry
            sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1] + 1
            mem[sp], mem[sp + 1] = ret & 255, ret >> 8
            r[su.F] &= ~1
        sim.run()
        steps += 1
        if steps > 200000:
            raise RuntimeError("no return")
    return bytes(text)


def shown(param, value):
    def setup(mem):
        mem[sym["golem_value"]] = param
        mem[sym["golem_status"]] = param
        mem[sym["golem_status"] + 1] = value
    return printed(sym["command_golem_control.show_set"], setup)


for param, value, want in ((0, 80, b"volume 80"), (0, 0, b"volume 0"), (0, 100, b"volume 100"),
                           (1, 0, b"fx off"), (1, 1, b"fx on"), (2, 0, b"channels std"),
                           (2, 1, b"channels alt"), (3, 0, b"thru off"), (3, 1, b"thru on"),
                           (4, 1, b"keys on"), (4, 0, b"keys off"),
                           (5, 72, b"bank 72"), (5, 0, b"bank 0"), (6, 1, b"loud on"), (6, 0, b"loud off")):
    got = shown(param, value)
    check(got == b"\rGolem: " + want + b"\r", f"prints {got!r}")

mem = fresh()
text = bytes(mem[sym["msg_usage"]:sym["msg_usage"] + 120]).split(b"\0")[0]
words = (b"play", b"note", b"status", b"engine", b"rom", b"soundfont", b"bank", b"output", b"usb", b"set", b"reset")
check(all(w in text for w in words) and b".guide golem" in text, f"usage {text!r}")

# 5. save, and the shared ending of the control commands
for line, value in (("save", 0), ("SAVE", 0), ("save clear", 1), ("Save  Clear ", 1), ("save:print", 0),
                    ("save clear:print", 1)):
    carry, mem = parse(line)
    got = (carry, mem[sym["command_mode"]], mem[sym["golem_command"]], mem[sym["golem_value"]])
    check(got == (1, CMD_SAVE, SAVE, value), f"'{line.strip()}' -> SAVE {value}")
for line in ("sav", "savex", "save clea", "save clearx", "save off", "save clear 1"):
    carry, _ = parse(line)
    check(carry == 0, f"'{line}' rejected")
for line, mode, command, value in (("engine mt32", 3, 0x01, 0), ("engine fluidsynth", 3, 0x01, 1),
                                   ("engine opl3", 3, 0x01, 2), ("ENGINE OPL3", 3, 0x01, 2),
                                   ("soundfont 7", 4, 0x03, 7), ("rom cm32l", 5, 0x02, 2),
                                   ("rom old", 5, 0x02, 0), ("usb bridge", 7, 0x04, 2), ("usb", 7, 0x04, 0x7F)):
    carry, mem = parse(line)
    got = (carry, mem[sym["command_mode"]], mem[sym["golem_command"]], mem[sym["golem_value"]])
    check(got == (1, mode, command, value), f"'{line}' still -> mode {mode} command {command:02X} {value:02X}")
for line in ("engine mt32 x", "soundfont 7 7", "rom new old", "engine", "engine opl", "engine opl33", "engine o"):
    carry, _ = parse(line)
    check(carry == 0, f"'{line}' rejected")

# 6. Status names the OPL3 engine
def status_text(engine, availability):
    def setup(mem):
        g = sym["golem_status"]
        mem[g:g + 7] = [0x7F, 0, availability, engine, 0x7F, 0x7F, 0x7F]
    return printed(sym["print_golem_status"], setup)


# With OPL3 active, a second exchange asks for the bank (SET_PARAM 5 7F)
mem = fresh()
g = sym["golem_status"]
mem[g:g + 7] = [0x7F, 0, 4, 2, 0x7F, 0x7F, 0x7F]
mem[sym["golem_transaction"]] = 0x10
s_ = sym["saved_sp"]; mem[s_], mem[s_ + 1] = 0xEFFE & 255, 0xEFFE >> 8
carry, written = call(sym["print_golem_status"], mem,
                      replies=HEADER + bytes([0x11, 0x40, SET_PARAM, 0xF7])
                      + HEADER + bytes([0x11, 0x41, SET_PARAM, 5, 72, 0xF7]))
text = bytes(call_printed)
check(written == HEADER + bytes([0x11, SET_PARAM, 5, 0x7F, 0xF7]), f"bank query {written.hex(' ').upper()}")
check(text.startswith(b"\rGolem: engine OPL3; bank 72; no MT32 ROM"), f"status with the bank: {text!r}")
got = status_text(0x7F, 0)
check(got.startswith(b"\rGolem: engine none;"), f"status with no engine: {got!r}")

# 7. play FILE BANK
for line, name, bank in (("play song.mid", b"song.mid", 0xFF), ("play song.mid 58", b"song.mid", 58),
                         ('play "my song.mid" 0', b"my song.mid", 0), ('PLAY "c:/m/x.mid"  127 ', b"c:/m/x.mid", 127),
                         ("play song.mid 72:print", b"song.mid", 72)):
    carry, mem = parse(line)
    got = bytes(mem[sym["filename"]:sym["filename"] + len(name) + 1])
    check(carry == 1 and mem[sym["command_mode"]] == 0 and got == name + b"\0" and mem[sym["play_bank"]] == bank,
          f"'{line.strip()}' -> play {name.decode()} bank {bank:02X}")
for line in ("play song.mid 128", "play song.mid x", "play song.mid 5 6", "play song.mid -1", "play song.mid 300"):
    carry, _ = parse(line)
    check(carry == 0, f"'{line}' rejected")

for bank, want in ((58, True), (0xFF, False)):
    mem = fresh()
    mem[sym["driver_caps"]] = 0x02          # RX
    mem[sym["driver_caps"] + 1] = 0         # output: the Golem
    mem[sym["play_bank"]] = bank
    carry, written = call(sym["select_engine"], mem)
    if want:
        check(written[:6] == HEADER and written[7:] == bytes([SET_PARAM, 5, 58, 0xF7]),
              f"select_engine sends the bank first: {written.hex(' ').upper()}")
    else:
        check(carry == 0 and written == b"", "without a bank select_engine sends nothing (.golem)")
sys.exit(1 if fails else 0)
