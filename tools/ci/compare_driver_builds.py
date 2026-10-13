"""Differential test of two builds of the golem-next resident driver.

Runs both images in a Z80 simulator (SkoolKit's, pure Python) against a model
of the Next UART and NextRegs and compares every observable result: registers
and carry of each call (QUERY, ACQUIRE, WRITE/READ, STATUS, DRAIN_STATUS,
RELEASE, an unsupported call), port writes, bytes sent, RX left, NextRegs and
caller memory. For refactors that must not change behaviour.

    git show main:src/driver/mt32drv.s > /tmp/old.s
    git clone --depth 1 https://github.com/skoolkid/skoolkit.git /tmp/skoolkit
    python3 tools/ci/compare_driver_builds.py /tmp/old.s src/driver/mt32drv.s include         --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, itertools, re, shutil, subprocess, sys, tempfile
from pathlib import Path

SJ = "sjasmplus"
ORG = 0x8000
RET = 0x7000

def assemble(src_text, inc_dir):
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "src" / "driver").mkdir(parents=True)
        shutil.copytree(inc_dir, t / "include")
        text = re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", src_text)
        text = re.sub(r"(?m)^(\s*)org \$0000\b", rf"\1org ${ORG:04x}", text)
        (t / "src" / "driver" / "d.s").write_text(text)
        subprocess.run([SJ, "--zxnext", "--nologo", "--msg=war", "--raw=out.bin", "d.s"],
                       cwd=t / "src" / "driver", check=True, capture_output=True)
        return (t / "src" / "driver" / "out.bin").read_bytes()[:512]

class Hw:
    def __init__(self, tx_cap, rx, nr11):
        self.tx_cap, self.rx = tx_cap, list(rx)
        self.tx = []            # bytes sent while the Pi UART is selected
        self.log = []           # every port write
        self.select = 0x00      # ESP selected by the caller
        self.frame = 0x18
        self.nr_sel = 0x7f
        self.nr = {0xa0: 0x05, 0xa2: 0x00, 0x11: nr11, 0x0b: 0x00}
    def pi(self):
        return self.select & 0x40
    def read_port(self, regs, port):
        if port == 0x133b:
            if not self.pi():
                return 0x10
            v = 0
            if self.rx: v |= 1
            if len(self.tx) >= self.tx_cap: v |= 2
            if not self.tx: v |= 0x10
            return v
        if port == 0x143b:
            return self.rx.pop(0) if (self.pi() and self.rx) else 0
        if port == 0x153b: return self.select
        if port == 0x163b: return self.frame
        if port == 0x243b: return self.nr_sel
        if port == 0x253b: return self.nr.get(self.nr_sel, 0)
        return 0xff
    def write_port(self, regs, port, value, t=0):
        self.log.append((port, value))
        if port == 0x133b and self.pi(): self.tx.append(value)
        elif port == 0x153b: self.select = value
        elif port == 0x163b: self.frame = value
        elif port == 0x243b: self.nr_sel = value
        elif port == 0x253b: self.nr[self.nr_sel] = value

MASK = set()      # (fn, register index in the result tuple) ignored by --mask
MASK_NR = set()   # NextRegs whose writes are ignored by --mask

def call(sim, mem, hw, fn, hl=0, de=0):
    r = sim.registers
    r[su.B], r[su.C] = fn, 0x2d
    r[su.D], r[su.E] = de >> 8, de & 255
    r[su.H], r[su.L] = hl >> 8, hl & 255
    r[su.A], r[su.F] = 0x5a, 0
    sp = 0xF000
    mem[sp - 2], mem[sp - 1] = RET & 255, RET >> 8
    r[su.SP] = sp - 2
    sim.run(ORG, RET)
    regs = tuple(r[i] for i in (su.B, su.C, su.D, su.E, su.H, su.L, su.SP, 8, 9, 10, 11))
    regs += tuple(r[i] for i in range(16, 24))   # alternate set
    if fn == 1:   # ACQUIRE leaves an internal table address in HL (undocumented)
        regs = regs[:4] + (None, None) + regs[6:]
    regs = tuple(None if (fn, i) in MASK else v for i, v in enumerate(regs))
    carry = r[su.F] & 1
    return (carry, r[su.A] if carry else None) + regs

def scenario(img, fn, acq, ptr, length, tx_cap, rx_n, nr11, fill):
    mem = [0] * 65536
    mem[ORG:ORG + 512] = list(img)
    for i in range(0x4000, 0x10000):
        if not (ORG <= i < ORG + 512) and not (0xEF00 <= i < 0xF000):
            mem[i] = (i * 7 + fill) & 255
    hw = Hw(tx_cap, [(0x80 + i) & 255 for i in range(rx_n)], nr11)
    sim = Simulator(mem, {"IX": 0x1234, "IY": 0x5678, "^BC": 0x1111, "^DE": 0x2222, "^HL": 0x3333, "^AF": 0x4444})
    sim.set_tracer(hw)
    out = [call(sim, mem, hw, 0)]
    if acq:
        out.append(call(sim, mem, hw, 1))
        hw.select = 0x00            # caller switches to the ESP between calls
    out.append(call(sim, mem, hw, fn, ptr, length))
    out.append(call(sim, mem, hw, 3))
    out.append(call(sim, mem, hw, 4))
    out.append(call(sim, mem, hw, 5))
    out.append(call(sim, mem, hw, 6, 0x9000, 4))
    out.append(call(sim, mem, hw, 8))   # first unsupported function number
    if MASK_NR:
        log, skip = [], False
        for port, value in hw.log:
            if skip and port == 0x253b:
                skip = False
                continue
            skip = port == 0x243b and value in MASK_NR
            if not skip:
                log.append((port, value))
        hw.log = log
        for reg in MASK_NR:
            hw.nr.pop(reg, None)
    data = bytes(b for i, b in enumerate(mem) if i >= 0x4000 and not (ORG <= i < ORG + 512) and not (0xEF00 <= i < 0xF000))
    return out, hw.log, hw.tx, hw.rx, dict(hw.nr), hw.select, hw.frame, hw.nr_sel, data

def main(old_src, new_src, inc):
    old, new = assemble(old_src, inc), assemble(new_src, inc)
    n = bad = 0
    for fn, acq, ptr, length, tx_cap, rx_n, nr11 in itertools.product(
            (2, 6), (0, 1), (0x3fff, 0x4000, 0xc000, 0xfff8, 0xffff),
            (0, 1, 5, 15, 16, 17, 256, 0xffff), (0, 1, 3, 100), (0, 1, 5, 20), (0, 7)):
        a = scenario(old, fn, acq, ptr, length, tx_cap, rx_n, nr11, 3)
        b = scenario(new, fn, acq, ptr, length, tx_cap, rx_n, nr11, 3)
        n += 1
        if a != b:
            bad += 1
            if bad <= 5:
                print("DIFF", dict(fn=fn, acq=acq, ptr=hex(ptr), len=length, tx=tx_cap, rx=rx_n, nr11=nr11))
                for x, y in zip(a, b):
                    if x != y: print("  old", str(x)[:300], "\n  new", str(y)[:300])
    print(f"{n} scenarios, {bad} differences")
    return 1 if bad else 0

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old"); ap.add_argument("new"); ap.add_argument("include")
    ap.add_argument("--sjasmplus", default="sjasmplus")
    ap.add_argument("--skoolkit", default="/tmp/skoolkit", help="SkoolKit source checkout")
    ap.add_argument("--mask", action="append", default=[], metavar="FN:REG",
                    help="ignore one output register of one function (REG: B C D E H L), "
                         "for intended ABI changes; e.g. 0:D 0:E 0:H 0:L")
    ap.add_argument("--mask-nextreg", action="append", default=[], metavar="NN",
                    help="ignore writes to this NextReg (hex), e.g. 0b")
    args = ap.parse_args()
    for item in args.mask:
        fn, reg = item.split(":")
        MASK.add((int(fn), "BCDEHL".index(reg.upper())))
    for item in args.mask_nextreg:
        MASK_NR.add(int(item, 16))
    SJ = args.sjasmplus
    sys.path.insert(0, args.skoolkit)
    from skoolkit.simulator import Simulator
    from skoolkit import simutils as su
    sys.exit(main(Path(args.old).read_text(), Path(args.new).read_text(), Path(args.include)))
