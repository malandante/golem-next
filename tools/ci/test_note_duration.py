"""Checks the duration of .golem note (#92) in a Z80 simulator.

Runs play_note of .GOLEM against a raster model of a 50 Hz Next with 48K timing
(224 T x 312 lines) and with +2A/+3 timing (228 T x 311 lines), in every video
timing of NextReg $11: the system clock is 28 MHz in HDMI and VGA 0 and up to
33 MHz in VGA 6, and the video and CPU clocks follow it. Checks that Note On to
Note Off lasts the requested seconds within 2 ms in all of them.

    python3 tools/ci/test_note_duration.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
ap.add_argument("--seconds", type=int, default=1)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
from skoolkit.simulator import Simulator
from skoolkit import simutils as su

REPO = args.repo
SECONDS = args.seconds
ORG = 0x8000

with tempfile.TemporaryDirectory() as t:
    t = Path(t); shutil.copytree(REPO / "src", t / "src"); shutil.copytree(REPO / "include", t / "include")
    f = t / "src/dot/golem_cli.s"; s = f.read_text()
    s = re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", s)
    s = s.replace("        org $2000", f"        org ${ORG:04x}", 1)
    f.write_text(s)
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "--sym=o.sym", "golem.s"],
                   cwd=t / "src/dot", check=True, capture_output=True)
    img = (t / "src/dot/o.bin").read_bytes()
    sym = {}
    for line in (t / "src/dot/o.sym").read_text().splitlines():
        m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", line)
        if m: sym[m.group(1).lower()] = int(m.group(2), 16)

def run(TLINE, LINES, TIMING=0, FSYS=28e6):
    mem = [0] * 65536
    mem[ORG:ORG + len(img)] = list(img)
    mem[0x0008] = 0xC9  # rst $08 lands here; handled in Python before executing
    for k, v in (("note_channel", 1), ("note_value", 60), ("note_velocity", 100), ("note_seconds", SECONDS)):
        mem[sym[k]] = v

    class Hw:
        def __init__(s, sim): s.sim = sim; s.sel = 0; s.nr = {5: 0x5B, 7: 0, 0x11: TIMING}; s.ticks = 0; s.lastT = 0
        def now(s):  # time in system clock ticks
            T = s.sim.registers[su.T]; d = T - s.lastT; s.lastT = T
            s.ticks += d * [8, 4, 2, 1][s.nr.get(7, 0) & 3]  # CPU at Fsys/8, /4, /2, /1
            return s.ticks
        def line(s):
            return (s.now() // (TLINE * 8)) % LINES
        def read_port(s, regs, port):
            if port == 0x243B: return s.sel
            if port == 0x253B:
                if s.sel == 0x1E: return s.line() >> 8
                if s.sel == 0x1F: return s.line() & 0xFF
                return s.nr.get(s.sel, 0)
            return 0xFF
        def write_port(s, regs, port, value, t=0):
            if port == 0x243B: s.sel = value
            elif port == 0x253B:
                if s.sel == 7: s.now()
                s.nr[s.sel] = value

    sim = Simulator(mem); hw = Hw(sim); sim.set_tracer(hw)
    r = sim.registers
    RET = 0x7000
    r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
    r[su.PC] = sym["play_note"]
    events = []
    steps = 0
    while r[su.PC] != RET:
        if r[su.PC] == 0x0008:
            sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1]
            call = mem[ret]; ret += 1
            mem[sp], mem[sp + 1] = ret & 255, ret >> 8
            if call == 0x92 and r[su.B] == 2:  # WRITE: take everything
                hl = r[su.H] * 256 + r[su.L]; de = r[su.D] * 256 + r[su.E]
                events.append((hw.now() / FSYS, bytes(mem[hl:hl + de])))
                r[su.B], r[su.C] = de >> 8, de & 255
                hl += de; r[su.H], r[su.L] = hl >> 8, hl & 255; r[su.D] = r[su.E] = 0
            r[su.F] &= ~1
        sim.run()
        steps += 1

    on = [t for t, b in events if b[0] & 0xF0 == 0x90][0]; off = [t for t, b in events if b[0] & 0xF0 == 0x80][0]
    return (off - on) * 1000

fails = 0
FSYS = (28e6, 200e6 / 7, 825e6 / 28, 30e6, 31e6, 32e6, 33e6, 27e6)
NAMES = ("HDMI/VGA 0", "VGA 1", "VGA 2", "VGA 3", "VGA 4", "VGA 5", "VGA 6", "27 MHz")
for timing in range(8):
    for name, tline, lines in (("48K", 224, 312), ("+2A/+3", 228, 311)):
        ms = run(tline, lines, timing, FSYS[timing])
        ok = abs(ms - SECONDS * 1000) <= 2
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'}: {NAMES[timing]}, {name} timing, note of {SECONDS} s lasts {ms:.2f} ms")
sys.exit(1 if fails else 0)
