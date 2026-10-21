"""Runs the .MIDIMON dot command in a Z80 simulator.

A model of NextZXOS and GOLEM.DRV serves M_P3DOS IDE_BANK (allocate and free
one bank), QUERY, ACQUIRE, READ (5 bytes at a time from a fixed stream) and
RELEASE; rst $10 output is captured and SPACE is pressed after a while.
Checks the printed lines (the Golem reply in the stream is not shown, a SysEx
longer than the buffer ends in "..."), that the bank is freed, the driver
released, and the CPU speed, MMU3 and NextReg selector restored. Also: without
GOLEM.DRV the command fails with its error report.

    python3 tools/ci/test_midimon_dot.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
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

with tempfile.TemporaryDirectory() as t:
    t = Path(t); shutil.copytree(args.repo / "src", t / "src"); shutil.copytree(args.repo / "include", t / "include")
    for f in (t / "src").rglob("*.s"):
        f.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", f.read_text()))
    f = t / "src/dot/midimon.s"   # the simulator's memory below $4000 is ROM: run it at $8000
    f.write_text(f.read_text().replace("        org $2000", f"        org ${ORG:04x}", 1))
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "midimon.s"],
                   cwd=t / "src/dot", check=True, capture_output=True)
    img = (t / "src/dot/o.bin").read_bytes()

LONG = bytes([0xF0, 0x43] + [i & 0x7F for i in range(200)] + [0xF7])
STREAM = (bytes.fromhex("90 3C 64 3E 64 F0 7D 47 4C 4D 01 12 41 05 00 50 F7 B0 01 40 E0 00 40 F8")
          + LONG + bytes.fromhex("80 3C 00"))
WANT = ["90 3C 64", "90 3E 64", "B0 01 40", "E0 00 40", "F8",
        " ".join(f"{b:02X}" for b in LONG[:128]) + " ...", "80 3C 00"]
RET = 0x7000


def run(driver=True):
    mem = [0] * 65536
    mem[ORG:ORG + len(img)] = list(img)
    mem[0x08] = mem[0x10] = 0xC9
    pending, printed, calls, polls = list(STREAM), [], [], [0]
    nr = {0x07: 1, 0x53: 11}
    sel = [0x24]

    class Ports:
        def read_port(self, regs, port):
            if port == 0x243B: return sel[0]
            if port == 0x253B: return nr.get(sel[0], 0)
            if port == 0x7FFE:
                polls[0] += 1
                return 0xFE if polls[0] > 400 else 0xFF
            return 0xFF
        def write_port(self, regs, port, value, t=0):
            if port == 0x243B: sel[0] = value
            elif port == 0x253B: nr[sel[0]] = value

    sim = Simulator(mem); sim.set_tracer(Ports()); r = sim.registers
    r[su.SP] = 0xFF00; mem[0xFF00], mem[0xFF01] = RET & 255, RET >> 8
    r[su.H], r[su.L] = 0, 0
    r[su.PC] = ORG
    steps = 0
    while r[su.PC] != RET and steps < 5_000_000:
        if r[su.PC] == 0x10:
            printed.append(r[su.A])
        if r[su.PC] == 0x08:
            sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1]
            call = mem[ret]; ret += 1
            mem[sp], mem[sp + 1] = ret & 255, ret >> 8
            if call == 0x94:  # M_P3DOS IDE_BANK: allocate (H=0,L=1) or free (L=3)
                calls.append(("bank",))
                r[su.F] |= 1
                r[su.E] = 50
            elif not driver:
                r[su.F] |= 1; r[su.A] = 0
            else:
                b = r[su.B]; calls.append(b)
                if b == 0:
                    r[su.B], r[su.C], r[su.D], r[su.E] = 0x4D, 0x54, 0, 3
                    r[su.H], r[su.L] = 0, 7
                elif b == 6:
                    hl = r[su.H] * 256 + r[su.L]; n = min(5, len(pending))
                    assert hl >= 0x4000, f"READ buffer at {hl:04X}"
                    mem[hl:hl + n] = pending[:n]; del pending[:n]
                    r[su.B], r[su.C] = 0, n
                r[su.F] &= ~1
        sim.run(); steps += 1
    text = bytes(printed).decode("latin1")
    lines = [line.strip() for line in text.split("\r") if line.strip()]
    return r, lines, calls, nr, sel[0], mem


fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


r, lines, calls, nr, sel, mem = run()
shown = [l for l in lines if not l.startswith("MIDIMON")]
check(r[su.PC] == RET and not (r[su.F] & 1), "ends without error when SPACE is pressed")
check(shown == WANT, f"printed {shown}")
check(lines[0].startswith("MIDIMON:") and lines[-1] == "MIDIMON: end", "start and end messages")
driver_calls = [c for c in calls if isinstance(c, int)]
check(driver_calls[:2] == [0, 1] and driver_calls[-1] == 5, f"QUERY, ACQUIRE ... RELEASE ({driver_calls[:2]}..{driver_calls[-1:]})")
check(sum(1 for c in calls if isinstance(c, tuple)) == 2, "one bank allocated and freed")
check(nr[0x07] == 1 and nr[0x53] == 11 and sel == 0x24, "speed, MMU3 and NextReg selector restored")
check(mem[23692] == 255, "scroll counter kept high")

r, lines, calls, nr, sel, mem = run(driver=False)
report = bytes(mem[r[su.H] * 256 + r[su.L]:][:40])
check(r[su.PC] == RET and (r[su.F] & 1) and r[su.A] == 0 and report.startswith(b"MIDIMON: GOLEM.DRV"),
      "without GOLEM.DRV: error report")
check(nr[0x07] == 1 and nr[0x53] == 11, "and the speed and MMU3 are restored")
sys.exit(1 if fails else 0)
