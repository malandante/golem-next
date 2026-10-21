"""Checks .golem usb (#85) and .golem reset (#104) in a Z80 simulator.

1. parse_command accepts `usb`, `usb off|on|bridge` (any case) and rejects
   near misses, setting golem_command = SET_USB_OUT and golem_value.
2. send_golem_control sends F0 7D 47 4C 4D 01 tt 04 vv F7 and, fed the
   firmware's ACCEPTED and READY (mode, device count), returns success with
   golem_status = mode, count. A READY with another mode is ignored, except
   for a query (7F), which accepts any mode.
3. `play` still stores the file name, now in the track_states area.
4. `reset` (any case) sets CMD_RESET and near misses are rejected; `rom new`
   still parses. reset_synth writes the MT-32 reset and GM System On.
5. print_z expands the PFX byte into a new line and "Golem: ".

    python3 tools/ci/test_golem_usb.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
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
CMD_USB = 7
CMD_RESET = 8
CMD_ROM = 5
SET_USB_OUT = 0x04
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


def call(entry, mem, regs=None, replies=b""):
    """Runs entry until it returns; rst $08 driver calls are served here."""
    mem[0x0008] = 0xC9
    sim = Simulator(mem); sim.set_tracer(Ports())
    r = sim.registers
    for k, v in (regs or {}).items(): r[k] = v
    r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
    r[su.PC] = entry
    written, pending, steps = bytearray(), bytearray(replies), 0
    while r[su.PC] != RET:
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


# 1. Command line
for line, value in (("usb", 0x7F), ("usb off", 0), ("usb on", 1), ("usb bridge", 2), ("USB Bridge", 2),
                    ("usb  on  ", 1), ("usb on:print", 1), ("usb\r", 0x7F)):
    mem = fresh()
    text = line.encode() + (b"" if line.endswith("\r") else b"\r")
    mem[CMDLINE:CMDLINE + len(text)] = list(text)
    carry, _ = call(sym["parse_command"], mem, {su.H: CMDLINE >> 8, su.L: CMDLINE & 255})
    ok = (carry == 1 and mem[sym["command_mode"]] == CMD_USB and mem[sym["golem_command"]] == SET_USB_OUT
          and mem[sym["golem_value"]] == value)
    check(ok, f"'{line.strip()}' -> SET_USB_OUT {value:02X}")

for line in ("usb of", "usb onx", "usb offf", "usbx", "usb maybe", "usb bridg", "us"):
    mem = fresh()
    text = line.encode() + b"\r"
    mem[CMDLINE:CMDLINE + len(text)] = list(text)
    carry, _ = call(sym["parse_command"], mem, {su.H: CMDLINE >> 8, su.L: CMDLINE & 255})
    check(carry == 0, f"'{line}' rejected")


# 2. Request and replies
def exchange(value, ready_mode, devices, tt=0x12):
    mem = fresh()
    mem[sym["golem_command"]] = SET_USB_OUT
    mem[sym["golem_value"]] = value
    mem[sym["golem_transaction"]] = tt
    accepted = HEADER + bytes([tt, 0x40, SET_USB_OUT, 0xF7])
    ready = HEADER + bytes([tt, 0x41, SET_USB_OUT, ready_mode, devices, 0xF7])
    carry, written = call(sym["send_golem_control"], mem, replies=accepted + ready)
    status = mem[sym["golem_status"]], mem[sym["golem_status"] + 1]
    return carry, written, status


for value, mode, devices in ((2, 2, 1), (1, 1, 0), (0, 0, 2), (0x7F, 1, 1)):
    carry, written, status = exchange(value, mode, devices)
    want = HEADER + bytes([0x12, SET_USB_OUT, value, 0xF7])
    check(written == want, f"request for {value:02X} is {written.hex(' ').upper()}")
    check(carry == 0 and status == (mode, devices),
          f"READY mode {mode} with {devices} device(s) accepted for {value:02X}")

carry, _, _ = exchange(1, 2, 1)
check(carry is None, "READY with a different mode is ignored")

# 3. The file name shares memory with track_states
mem = fresh()
text = b'play "my song.mid"\r'
mem[CMDLINE:CMDLINE + len(text)] = list(text)
carry, _ = call(sym["parse_command"], mem, {su.H: CMDLINE >> 8, su.L: CMDLINE & 255})
name = bytes(mem[sym["filename"]:sym["filename"] + 12])
check(carry == 1 and sym["filename"] == sym["track_states"] and name == b"my song.mid\0",
      "play stores the file name at track_states")

# 4. .golem reset
def parse(line):
    mem = fresh()
    text = line.encode() + b"\r"
    mem[CMDLINE:CMDLINE + len(text)] = list(text)
    carry, _ = call(sym["parse_command"], mem, {su.H: CMDLINE >> 8, su.L: CMDLINE & 255})
    return carry, mem


for line in ("reset", "RESET", "Reset  ", "reset:print"):
    carry, mem = parse(line)
    check(carry == 1 and mem[sym["command_mode"]] == CMD_RESET, f"'{line.strip()}' -> reset")
for line in ("rese", "resetx", "reset on", "re", "rset"):
    carry, _ = parse(line)
    check(carry == 0, f"'{line}' rejected")
carry, mem = parse("rom new")
check(carry == 1 and mem[sym["command_mode"]] == CMD_ROM, "'rom new' still parses")

mem = fresh()
_, written = call(sym["reset_synth"], mem)
want = bytes([0xF0, 0x41, 0x10, 0x16, 0x12, 0x7F, 0x00, 0x00, 0x00, 0x01, 0xF7, 0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7])
check(written == want, f"reset_synth writes {written.hex(' ').upper()}")

# 5. print_z and the shared "Golem: " prefix
def printed(address):
    mem = fresh()
    mem[0x0010] = 0xC9
    sim = Simulator(mem)
    r = sim.registers
    r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
    r[su.H], r[su.L] = address >> 8, address & 255
    r[su.PC] = sym["print_z"]
    text, steps = bytearray(), 0
    while r[su.PC] != RET:
        if r[su.PC] == 0x0010:
            text.append(r[su.A])
        sim.run()
        steps += 1
        if steps > 100000:
            raise RuntimeError("no return")
    return bytes(text)


check(printed(sym["msg_playing"]) == b"\rGolem: playing (SPACE stops)", "print_z: PFX -> CR + 'Golem: '")
check(printed(sym["msg_done"]) == b"\rGolem: playback finished\r", "print_z: text after the prefix")
check(printed(sym["text_output_left"]) == b"left joystick port, pin 7", "print_z: plain text unchanged")

sys.exit(1 if fails else 0)
