"""Builds examples/midimon.bas with ZX Basic and runs it in a Z80 simulator.

The program includes the ZX Basic binding src/lib/midiin.bas, so this checks
the binding and the library together: a model of GOLEM.DRV serves ACQUIRE,
READ (5 bytes at a time from a fixed stream) and RELEASE, rst $10 output is
captured, and SPACE is reported pressed after a while. The printed lines must
be the messages of the stream in hexadecimal, without the Golem reply.

    python3 tools/ci/test_midimon.py --zxbc /tmp/zxbasic/zxbc.py --skoolkit /tmp/skoolkit
"""
import argparse, shutil, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--zxbc", default="zxbc.py")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
from skoolkit.simulator import Simulator
from skoolkit import simutils as su

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    (t / "lib").mkdir(); (t / "examples").mkdir()
    for name in ("midiin.bas", "midiin.s"):
        shutil.copy(args.repo / "src/lib" / name, t / "lib")
    shutil.copy(args.repo / "include/mt32_api.inc", t / "lib")
    shutil.copy(args.repo / "src/examples/midimon.bas", t / "examples")
    subprocess.run([sys.executable, args.zxbc, "midimon.bas", "-o", "midimon.bin"], cwd=t / "examples",
                   check=True, capture_output=True)
    img = (t / "examples/midimon.bin").read_bytes()

STREAM = bytes.fromhex("90 3C 64 3E 64 F0 7D 47 4C 4D 01 12 41 05 00 50 F7 "
                       "F0 41 10 16 12 10 00 16 50 0A F7 C0 05 F8")
WANT = ["90 3C 64", "90 3E 64", "F0 41 10 16 12 10 00 16 50 0A F7", "C0 05", "F8"]

mem = [0] * 65536
mem[32768:32768 + len(img)] = list(img)
mem[0x10] = mem[0x08] = 0xC9
pending, printed, calls, polls = list(STREAM), [], [], [0]


class Ports:
    def read_port(self, regs, port):
        if port == 0x7FFE:
            polls[0] += 1
            return 0xFE if polls[0] > 40 else 0xFF   # SPACE after 40 polls
        return 0xFF
    def write_port(self, regs, port, value, t=0): pass


sim = Simulator(mem); sim.set_tracer(Ports()); r = sim.registers
r[su.SP] = 0xFF00; mem[0xFF00], mem[0xFF01] = 0x00, 0x70
r[su.PC] = 32768
steps = 0
while r[su.PC] != 0x7000 and steps < 3_000_000:
    if r[su.PC] == 0x10:
        printed.append(r[su.A])
    if r[su.PC] == 0x08:
        sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1] + 1
        mem[sp], mem[sp + 1] = ret & 255, ret >> 8
        calls.append(r[su.B])
        if r[su.B] == 6:
            hl = r[su.H] * 256 + r[su.L]; n = min(5, len(pending))
            mem[hl:hl + n] = pending[:n]; del pending[:n]
            r[su.B], r[su.C] = 0, n
        r[su.F] &= ~1
    sim.run(); steps += 1

lines = [line.strip() for line in bytes(printed).decode("latin1").split("\r") if line.strip()]
fails = 0
for ok, text in ((r[su.PC] == 0x7000, "the program ends when SPACE is pressed"),
                 (calls[:1] == [1] and calls[-1:] == [5], f"ACQUIRE first, RELEASE last ({calls[0]}..{calls[-1]})"),
                 (lines == WANT, f"printed {lines}")):
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")
sys.exit(1 if fails else 0)
