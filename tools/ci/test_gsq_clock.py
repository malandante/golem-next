"""Checks the millisecond clock of .GSQ (clock_init, clock_now) in a Z80 simulator.

The clock counts raster lines and converts them to milliseconds. A raster model
runs at the system clock of each video timing in NextReg $11 (28 MHz for HDMI
and VGA 0, up to 33 MHz for VGA 6, 27 MHz for timing 7), with 48K (224 T x 312
lines) and +2A/+3 (228 T x 311 lines) frames. After about two seconds of calls
to clock_now, the clock must be within 2 ms of the real time.

    python3 tools/ci/test_gsq_clock.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
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

ORG = 0x8000
RET = 0x7000

with tempfile.TemporaryDirectory() as t:
    t = Path(t); shutil.copytree(args.repo / "src", t / "src"); shutil.copytree(args.repo / "include", t / "include")
    for f in (t / "src").rglob("*.s"):
        f.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", f.read_text()))
    f = t / "src/dot/gsq.s"
    f.write_text(f.read_text().replace("        org $2000", f"        org ${ORG:04x}", 1))
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "--sym=o.sym", "gsq.s"],
                   cwd=t / "src/dot", check=True, capture_output=True)
    img = (t / "src/dot/o.bin").read_bytes()
    sym = {}
    for line in (t / "src/dot/o.sym").read_text().splitlines():
        m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", line)
        if m: sym[m.group(1).lower()] = int(m.group(2), 16)


def run(tline, lines, timing, fsys, seconds=2.0):
    mem = [0] * 65536
    mem[ORG:ORG + len(img)] = list(img)

    class Hw:
        def __init__(s, sim): s.sim = sim; s.sel = 0; s.nr = {7: 0, 0x11: timing}; s.ticks = 0; s.lastT = 0
        def now(s):  # system clock ticks
            T = s.sim.registers[su.T]; d = T - s.lastT; s.lastT = T
            s.ticks += d * [8, 4, 2, 1][s.nr.get(7, 0) & 3]
            return s.ticks
        def line(s):
            return (s.now() // (tline * 8)) % lines
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

    def call(entry):
        r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
        r[su.PC] = entry
        while r[su.PC] != RET:
            sim.run()
        return r[su.D] * 256 + r[su.E]

    call(sym["clock_init"])
    start = hw.now()
    elapsed_ms, previous, total = 0.0, 0, 0
    while elapsed_ms < seconds * 1000:
        now = call(sym["clock_now"])
        total += (now - previous) & 0xFFFF
        previous = now
        elapsed_ms = (hw.now() - start) / fsys * 1000
    return total, elapsed_ms


FSYS = (28e6, 200e6 / 7, 825e6 / 28, 30e6, 31e6, 32e6, 33e6, 27e6)
NAMES = ("HDMI/VGA 0", "VGA 1", "VGA 2", "VGA 3", "VGA 4", "VGA 5", "VGA 6", "27 MHz")
fails = 0
for timing in range(8):
    for name, tline, lines in (("48K", 224, 312), ("+2A/+3", 228, 311)):
        clock, real = run(tline, lines, timing, FSYS[timing])
        ok = abs(clock - real) <= 2
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'}: {NAMES[timing]}, {name}: clock {clock} ms after {real:.1f} ms")
sys.exit(1 if fails else 0)
