"""Checks the cleanup after SPACE cancels playback, in a Z80 simulator.

The sweep of Sustain off, All Notes Off and All Sound Off must reach all 16
channels even with SPACE still held and the driver's buffer full now and
then. Before the fix it stopped at channel 7: waiting for the driver, the
cleanup checked SPACE again and gave up (seen on hardware, OPL3 capture of
2026-10-21).

    python3 tools/ci/test_golem_cancel.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
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
RET = 0x7000
FN_WRITE = 0x02
LINES = 312

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
    """SPACE held; the raster advances one line per LSB read."""
    def __init__(self, space):
        self.space, self.reg, self.line = space, 0, 0

    def read_port(self, regs, port):
        if port == 0x7FFE:
            return 0xFE if self.space else 0xFF
        if port == 0x253B:
            if self.reg == 0x1F:
                self.line = (self.line + 1) % LINES
                return self.line & 0xFF
            if self.reg == 0x1E:
                return self.line >> 8
        return 0xFF

    def write_port(self, regs, port, value, t=0):
        if port == 0x243B:
            self.reg = value


def cleanup_sweep(space, cancelled, busy_every):
    """all_notes_off with a driver that is full on every busy_every-th WRITE."""
    mem = [0] * 65536
    mem[ORG:ORG + len(img)] = list(img)
    mem[0x0008] = 0xC9
    mem[sym["cancelled"]] = cancelled
    mem[sym["scheduler_active"]] = 0
    sim = Simulator(mem); sim.set_tracer(Ports(space))
    r = sim.registers
    r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
    r[su.PC] = sym["all_notes_off"]
    written, writes, steps = bytearray(), 0, 0
    while r[su.PC] != RET:
        if r[su.PC] == 0x0008:
            sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1] + 1
            mem[sp], mem[sp + 1] = ret & 255, ret >> 8
            hl = r[su.H] * 256 + r[su.L]; de = r[su.D] * 256 + r[su.E]
            if r[su.B] == FN_WRITE:
                writes += 1
                n = 0 if writes % busy_every == 0 else de
                written += bytes(mem[hl:hl + n])
                r[su.B], r[su.C] = n >> 8, n & 255
                hl += n; de -= n
                r[su.H], r[su.L], r[su.D], r[su.E] = hl >> 8, hl & 255, de >> 8, de & 255
            r[su.F] &= ~1
        sim.run()
        steps += 1
        if steps > 5000000:
            raise RuntimeError("no return")
    return written


def sweep():
    out = bytearray()
    for ch in range(16):
        out += bytes([0xB0 | ch, 0x40, 0, 0xB0 | ch, 0x7B, 0, 0xB0 | ch, 0x78, 0])
    return bytes(out)


fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


for busy in (2, 3, 8):
    got = cleanup_sweep(space=True, cancelled=1, busy_every=busy)
    check(got == sweep(), f"SPACE held after a cancel, driver full every {busy} writes: "
                          f"all 16 channels ({len(got)} of 144 bytes)")
got = cleanup_sweep(space=False, cancelled=0, busy_every=3)
check(got == sweep(), "no cancel, driver full every 3 writes: all 16 channels")

sys.exit(1 if fails else 0)
