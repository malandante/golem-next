"""Runs the ZX Basic binding of the gp_* library (src/lib/gparam.bas) in a Z80
simulator.

tests/zxbasic/gparam_test.bas is compiled with ZX Basic (zxbc) at $6000; the
library bank (src/lib/gparam_c000.s, built with sjasmplus) is bank 40, mapped
by the binding in slot 6. NextReg writes really page banks in slots 4 and 6;
GOLEM.DRV is modelled (WRITE takes 1-16 bytes at random, READ gives what has
arrived, both checking that the ROM is in MMU0/1 and that the buffer pointer
is in IX as NextZXOS gives it to programs) and answers with the Golem model of
gparam_model.py. Checks the signature, a name, a confirmed write read back, a
refused value with its error and position, and a 10000-byte bank downloaded
into two banks and uploaded again, unchanged.

    python3 tools/ci/test_gparam_bas.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, random, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--zxbc", default="zxbc")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from skoolkit.simulator import Simulator
from skoolkit import simutils as su
from gparam_model import ModelGolem

ORG = 0x6000
RET = 0x5F00

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    shutil.copytree(args.repo / "src", t / "src"); shutil.copytree(args.repo / "include", t / "include")
    shutil.copytree(args.repo / "tests", t / "tests")
    for f in (t / "src").rglob("*.s"):
        f.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", f.read_text()))
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=lib.bin", "gparam_c000.s"],
                   cwd=t / "src/lib", check=True, capture_output=True)
    library = (t / "src/lib/lib.bin").read_bytes()
    zxbc = [sys.executable, args.zxbc] if args.zxbc.endswith(".py") else [args.zxbc]
    out = subprocess.run(zxbc + ["gparam_test.bas", "-o", str(t / "prog.bin"), f"--org={ORG}", "-f", "bin"],
                         cwd=t / "tests/zxbasic", capture_output=True, text=True)
    if out.returncode:
        print(out.stdout, out.stderr)
        sys.exit(1)
    program = (t / "prog.bin").read_bytes()

mem = [0] * 65536
mem[ORG:ORG + len(program)] = list(program)
mem[0x08] = mem[0x10] = 0xC9
banks = {40: bytearray(library.ljust(8192, b"\0"))}
golem = ModelGolem("mt32-pi golem-1.3.0")
golem.blob = bytes(b"WOPL3-BANK\0" + bytes((i * 11 + (i >> 8)) & 255 for i in range(10000 - 11)))
original_blob = golem.blob                 # 10000 bytes: across banks 50 and 51
rng = random.Random(1)
nr = {0x50: 0xFF, 0x51: 0xFF, 0x54: 4, 0x56: 0}
sel = [0]
mapped = {0x54: None, 0x56: None}
printed = []
problems = []


def page(slot, bank):
    base = (slot - 0x50) * 0x2000
    old = mapped[slot]
    if old is not None:
        banks[old][:] = bytes(mem[base:base + 0x2000])
    mapped[slot] = bank
    if bank not in banks:
        banks[bank] = bytearray(8192)
    mem[base:base + 0x2000] = list(banks[bank])


class Ports:
    def read_port(self, regs, port):
        if port == 0x243B: return sel[0]
        if port == 0x253B: return nr.get(sel[0], 0)
        return 0xFF

    def write_port(self, regs, port, value, t=0):
        if port == 0x243B:
            sel[0] = value
        elif port == 0x253B:
            if sel[0] in mapped:
                page(sel[0], value)
            nr[sel[0]] = value


sim = Simulator(mem); sim.set_tracer(Ports()); r = sim.registers
r[su.SP] = 0x5FF0; mem[0x5FF0], mem[0x5FF1] = RET & 255, RET >> 8
r[su.PC] = ORG
steps = 0
while r[su.PC] != RET and steps < 60_000_000:
    pc = r[su.PC]
    if pc == 0x10:
        printed.append(r[su.A])
    elif pc == 0x08:
        sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1]
        assert mem[ret] == 0x92, "M_DRVAPI"
        ret += 1; mem[sp], mem[sp + 1] = ret & 255, ret >> 8
        if nr[0x50] != 0xFF or nr[0x51] != 0xFF:
            problems.append("driver called without the ROM in MMU0/1")
        ix = r[su.IXh] * 256 + r[su.IXl]
        de = r[su.D] * 256 + r[su.E]
        if r[su.B] == 2:
            n = min(de, 16, rng.randint(1, 16))
            golem.receive(mem[ix:ix + n])
        elif r[su.B] == 6:
            data = golem.take(min(de, 16))
            n = len(data)
            mem[ix:ix + n] = list(data)
        else:
            problems.append(f"driver function {r[su.B]}")
            n = 0
        r[su.B], r[su.C] = 0, n
        r[su.F] &= ~1
    sim.run()
    steps += 1

text = bytes(printed).decode("latin1").strip()
print(text)
fails = 0


def check(ok, what):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {what}")


fields = dict(re.findall(r"(\S)=(\d+)", text))
check(r[su.PC] == RET, "the program ends")
check(not problems, f"driver calls: ROM in MMU0/1, buffer in IX {problems[:3]}")
check(text.startswith("I=000 E=000 N=002 mt32-pi golem-1.3.0 "), "GpInit (signature) and GpInfo page 1")
check("W=002 R=002 a=001 b=000" in text, "confirmed write, then read back")
check("X=003 E=004 P=001" in text, "refused value: error 04 at position 1")
size = len(original_blob)
check(f"G=002 L={size & 255:03d} H={size >> 8:03d}" in text, f"bank of {size} bytes downloaded")
flat = bytes(banks[50]) + bytes(banks.get(51, bytes(8192)))
check(flat[:size] == original_blob, "it is in banks 50 and 51")
check("U=002 E=000" in text and golem.blob == original_blob, "uploaded back unchanged")
check(nr[0x54] == 4 and nr[0x56] == 0, "slots 4 and 6 restored")
sys.exit(1 if fails else 0)
