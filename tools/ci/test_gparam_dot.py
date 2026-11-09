"""Runs the .GPARAM dot command in a Z80 simulator.

A model of NextZXOS (IDE_BANK, M_GETSETDRV, F_OPEN, F_READ, F_WRITE, F_CLOSE
on files kept in memory) and of GOLEM.DRV (QUERY, ACQUIRE, WRITE, READ,
RELEASE) connects the command to the Golem model of gparam_model.py; rst $10
output is captured, HALT ends a frame, MMU4 really pages the banks in. Checks
info, get, set (also a refused value), sbi (a .SBI instrument as a melodic
program and as a drum, against a copy of golembank.py's conversion), put of a
120000-byte WOPL file (over 64K), save of
the working bank, the usage report, and that every bank is freed, the driver
released, the file closed and MMU3, MMU4 and the NextReg selector restored.

    python3 tools/ci/test_gparam_dot.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, random, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from skoolkit.simulator import Simulator
from skoolkit import simutils as su
from gparam_model import ModelGolem

ORG = 0xA000   # below $4000 the simulator has ROM; $8000 is the MMU4 window

with tempfile.TemporaryDirectory() as t:
    t = Path(t); shutil.copytree(args.repo / "src", t / "src"); shutil.copytree(args.repo / "include", t / "include")
    for f in (t / "src").rglob("*.s"):
        f.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", f.read_text()))
    f = t / "src/dot/gparam.s"
    f.write_text(f.read_text().replace("        org $2000", f"        org ${ORG:04x}", 1))
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "gparam.s"],
                   cwd=t / "src/dot", check=True, capture_output=True)
    img = (t / "src/dot/o.bin").read_bytes()
    size = len(img)

RET = 0x7000
ARGS = 0x5D00


def run(line, files=None, driver=True, golem=None, seed=1):
    mem = [0] * 65536
    mem[ORG:ORG + len(img)] = list(img)
    mem[0x08] = mem[0x10] = 0xC9
    text = line.encode() + b"\r"
    mem[ARGS:ARGS + len(text)] = list(text)
    golem = golem or ModelGolem("mt32-pi golem-1.3.0")
    files = files if files is not None else {}
    rng = random.Random(seed)
    printed, calls = [], []
    banks, free = {}, list(range(40, 80))
    handles = {}
    nr = {0x53: 11, 0x54: 4}
    sel = [0x24]
    window = [None]                       # the bank seen at $8000

    def page(bank):
        if window[0] in banks:
            banks[window[0]][:] = bytes(mem[0x8000:0xA000])
        window[0] = bank
        mem[0x8000:0xA000] = list(banks[bank]) if bank in banks else [0] * 8192

    class Ports:
        def read_port(self, regs, port):
            if port == 0x243B: return sel[0]
            if port == 0x253B: return nr.get(sel[0], 0)
            if port == 0x7FFE: return 0xFF
            return 0xFF

        def write_port(self, regs, port, value, t=0):
            if port == 0x243B:
                sel[0] = value
            elif port == 0x253B:
                if sel[0] == 0x54:
                    page(value)
                nr[sel[0]] = value

    sim = Simulator(mem); sim.set_tracer(Ports()); r = sim.registers
    r[su.SP] = 0xFF00; mem[0xFF00], mem[0xFF01] = RET & 255, RET >> 8
    r[su.H], r[su.L] = ARGS >> 8, ARGS & 255
    r[su.PC] = ORG
    hl = lambda: r[su.H] * 256 + r[su.L]
    de = lambda: r[su.D] * 256 + r[su.E]
    bc = lambda: r[su.B] * 256 + r[su.C]

    def set_bc(n):
        r[su.B], r[su.C] = n >> 8, n & 255

    steps = 0
    while r[su.PC] != RET and steps < 40_000_000:
        pc = r[su.PC]
        if pc == 0x10:
            printed.append(r[su.A])
        elif mem[pc] == 0x76:             # HALT: the frame ends
            r[su.PC] = pc + 1
            continue
        elif pc == 0x08:
            sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1]
            call = mem[ret]; ret += 1
            mem[sp], mem[sp + 1] = ret & 255, ret >> 8
            r[su.F] &= ~1
            if call == 0x94:              # IDE_BANK: alternate registers carry H/L
                op = r[su.xL]
                if op == 1:
                    b = free.pop(0); banks[b] = bytearray(8192); r[su.E] = b; r[su.F] |= 1
                    calls.append(("alloc", b))
                else:
                    b = r[su.xE]
                    calls.append(("free", b)); free.append(b); banks.pop(b, None)
                    r[su.F] |= 1
            elif call == 0x89:            # M_GETSETDRV
                r[su.A] = ord("C")
            elif call == 0x9A:            # F_OPEN
                name = bytes(mem[hl():hl() + 64]).split(b"\0")[0].decode()
                h = len(handles) + 1
                if r[su.B] & 2:
                    files[name] = bytearray(); handles[h] = [name, 0]
                elif name in files:
                    handles[h] = [name, 0]
                else:
                    h = None
                    r[su.F] |= 1; r[su.A] = 5
                if h:
                    calls.append(("open", name)); r[su.A] = h
            elif call == 0x9B:            # F_CLOSE
                calls.append(("close", handles.pop(r[su.A])[0]))
            elif call == 0x9D:            # F_READ
                name, pos = handles[r[su.A]]
                data = files[name][pos:pos + bc()]
                mem[hl():hl() + len(data)] = list(data)
                handles[r[su.A]][1] += len(data); set_bc(len(data))
            elif call == 0x9E:            # F_WRITE
                name = handles[r[su.A]][0]
                files[name] += bytes(mem[hl():hl() + bc()])
            elif call == 0x92:            # M_DRVAPI
                f = r[su.B]
                calls.append(("drv", f))
                if not driver:
                    r[su.F] |= 1; r[su.A] = 0
                elif f == 0:
                    r[su.H], r[su.L] = 0, 7
                elif f == 2:
                    assert hl() >= 0x4000
                    n = min(de(), 16, rng.randint(1, 16))
                    golem.receive(mem[hl():hl() + n]); set_bc(n)
                elif f == 6:
                    assert hl() >= 0x4000
                    data = golem.take(min(de(), 16))
                    mem[hl():hl() + len(data)] = list(data); set_bc(len(data))
        sim.run(); steps += 1
    out = bytes(printed).decode("latin1")
    lines = [l.strip() for l in out.split("\r") if l.strip()]
    return dict(r=r, lines=lines, calls=calls, nr=nr, sel=sel[0], files=files, golem=golem, mem=mem,
                banks=banks, handles=handles, steps=steps)


fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


def clean(res, what):
    r, calls = res["r"], res["calls"]
    alloc = [c[1] for c in calls if c[0] == "alloc"]
    freed = [c[1] for c in calls if c[0] == "free"]
    drv = [c[1] for c in calls if c[0] == "drv"]
    check(r[su.PC] == RET, f"{what}: returns")
    check(sorted(alloc) == sorted(freed), f"{what}: every bank freed ({len(alloc)})")
    check(1 not in drv or drv[-1] == 5, f"{what}: driver released once acquired")
    check(not res["handles"], f"{what}: no file left open")
    check(res["nr"][0x53] == 11 and res["nr"][0x54] == 4 and res["sel"] == 0x24,
          f"{what}: MMU3, MMU4 and NextReg selector restored")


print(f"GPARAM is {size} bytes")
check(size <= 8192, "fits a dot command")

res = run("info")
check(res["lines"][:3] == ["Golem firmware 1.3.0, protocol 1.1", "OPL3: 79 banks, chips 1", "mt32-pi golem-1.3.0"],
      f"info: {res['lines']}")
clean(res, "info")

g = ModelGolem()
g.settings[0:3] = [0x37, 1, 0x10]
res = run("get 10 0 3", golem=g)
check(res["lines"] == ["000000 37 01 10"], f"get: {res['lines']}")
g.instr[2] = list(range(128))
res = run("get 01 100 12", golem=g)
check(res["lines"] == ["000100 00 01 02 03 04 05 06 07", "000108 08 09 0A 0B 0C 0D 0E 0F", "000110 10 11"],
      f"get 18 bytes over lines: {res['lines']}")
clean(res, "get")

g = ModelGolem()
res = run("SET 10 0 40 1", golem=g)
check(res["lines"] == ["OK"] and g.settings[0:2] == [0x40, 1], f"set: {res['lines']} {g.settings[0:2]}")
res = run("set 10 0 32 65", golem=g)
check(res["lines"] == ["Golem error 04 value at 1"], f"set refused: {res['lines']}")
clean(res, "set")

bank = bytes(b"WOPL3-BANK\0" + bytes((i * 7 + (i >> 11)) & 255 for i in range(120000 - 11)))
g = ModelGolem()
res = run("put c:/opl3/test.wopl", files={"c:/opl3/test.wopl": bank}, golem=g)
check(g.blob == bank, f"put: the Golem got the 120000 bytes ({len(g.blob)})")
check(res["lines"] == ["Sending 120000 bytes", "Working OPL3 bank loaded"], f"put: {res['lines']}")
clean(res, "put")

g = ModelGolem()
g.blob = bytes(b"WOPL3-BANK\0" + bytes((i * 3 + (i >> 10)) & 255 for i in range(100000)))
res = run('save "c:/out.wopl"', golem=g)
check(bytes(res["files"].get("c:/out.wopl", b"")) == g.blob, f"save: file of {len(res['files'].get('c:/out.wopl', b''))} bytes")
check(res["lines"] == [f"Saved {len(g.blob)} bytes"], f"save: {res['lines']}")
clean(res, "save")

# The MT-32 dump: "mt32" before the name, BLOB type 04 both ways
dump = bytes((0xF0, 0x41, 0x10, 0x16, 0x12)) + bytes((i * 5) & 0x7F for i in range(17841 - 6)) + bytes((0xF7,))
g = ModelGolem()
res = run("put MT32 c:/sounds/my.syx", files={"c:/sounds/my.syx": dump}, golem=g)
check(g.mt32 == dump and g.blob_types == [4], f"put mt32: {len(g.mt32)} bytes, types {g.blob_types}")
check(res["lines"] == ["Sending 17841 bytes", "MT-32 dump loaded"], f"put mt32: {res['lines']}")
clean(res, "put mt32")
g = ModelGolem()
g.mt32 = dump
res = run("save mt32 c:/back.syx", golem=g)
check(bytes(res["files"].get("c:/back.syx", b"")) == dump and set(g.blob_types) == {4},
      f"save mt32: {len(res['files'].get('c:/back.syx', b''))} bytes, types {g.blob_types}")
check(res["lines"] == ["Saved 17841 bytes"], f"save mt32: {res['lines']}")
clean(res, "save mt32")
# FluidSynth's effects: "fx", BLOB type 03 both ways
profile = b"reverb = off\nchorus_type = triangle\n" * 10
g = ModelGolem()
res = run("put FX c:/golem/now.cfg", files={"c:/golem/now.cfg": profile}, golem=g)
check(g.fx == profile and g.blob_types == [3], f"put fx: {len(g.fx)} bytes, types {g.blob_types}")
check(res["lines"] == [f"Sending {len(profile)} bytes", "Effects loaded"], f"put fx: {res['lines']}")
clean(res, "put fx")
g = ModelGolem()
g.fx = profile
res = run('save fx "c:/golem/back.cfg"', golem=g)
check(bytes(res["files"].get("c:/golem/back.cfg", b"")) == profile and set(g.blob_types) == {3},
      f"save fx: {len(res['files'].get('c:/golem/back.cfg', b''))} bytes, types {g.blob_types}")
check(res["lines"] == [f"Saved {len(profile)} bytes"], f"save fx: {res['lines']}")
clean(res, "save fx")
# Nothing after the file name: a word there is not taken for something else
for line in ("save c:/golem/a.wop c:/golem/b.wop", "put fx now.cfg extra", 'save "c:/golem/a.wop" x'):
    g = ModelGolem()
    res = run(line, files={"c:/golem/a.wop": bank, "now.cfg": b"reverb = on\n"}, golem=g)
    report = bytes(res["mem"][res["r"][su.H] * 256 + res["r"][su.L]:][:12])
    check(res["r"][su.F] & 1 and report.startswith(b".gparam"), f"'{line}': usage, got {report}")
    check(g.blob_types == [], f"{line}: nothing sent ({g.blob_types})")
    clean(res, line)
# Without it, still the OPL3 bank (type 01), also for a file whose name starts with mt32
g = ModelGolem()
res = run("put mt32bank.wop", files={"mt32bank.wop": bank}, golem=g)
check(g.blob == bank and g.blob_types == [1], f"put mt32bank.wop is an OPL3 bank: types {g.blob_types}")
clean(res, "put mt32bank")

# A Golem that does not answer: the time-out, and the driver given back
g = ModelGolem()
g.silent = True
res = run("info", golem=g)
check(res["lines"] == ["Golem error 20 no answer"], f"no answer: {res['lines']}")
clean(res, "no answer")

res = run("")
report = bytes(res["mem"][res["r"][su.H] * 256 + res["r"][su.L]:][:40])
check(res["r"][su.F] & 1 and res["r"][su.A] == 0 and report.startswith(b".gparam info"), f"usage report: {report[:30]}")
clean(res, "usage")

res = run("info", driver=False)
report = bytes(res["mem"][res["r"][su.H] * 256 + res["r"][su.L]:][:40])
check(res["r"][su.F] & 1 and report.startswith(b"GPARAM: GOLEM.DRV"), f"without GOLEM.DRV: {report[:30]}")
clean(res, "no driver")

res = run("put nothere.wopl")
report = bytes(res["mem"][res["r"][su.H] * 256 + res["r"][su.L]:][:40])
check(res["r"][su.F] & 1 and report.startswith(b"GPARAM: cannot open"), f"missing file: {report[:30]}")
clean(res, "missing file")

# sbi: the record golembank.py would make
def sbi_record(sbi, key):
    r = sbi[36:47]
    rec = [0] * 128
    rec[4] = key
    rec[5] = rec[6] = rec[7] = rec[8] = rec[0x11] = rec[0x12] = 64
    rec[0x09], rec[0x0A] = (r[10] >> 1) & 7, r[10] & 1
    for at, b in ((0x20, 1), (0x30, 0)):           # carrier, modulator
        ch, lv, ad, sr, wv = r[b], r[b + 2], r[b + 4], r[b + 6], r[b + 8]
        rec[at:at + 12] = [ch >> 7 & 1, ch >> 6 & 1, ch >> 5 & 1, ch >> 4 & 1, ch & 15,
                           lv >> 6, lv & 63, ad >> 4, ad & 15, sr >> 4, sr & 15, wv & 7]
    name = sbi[4:36].split(b"\0")[0][:31]
    rec[0x60:0x60 + len(name)] = [c & 0x7F for c in name]
    return rec


sbi = b"SBI\x1a" + b"Brass 1".ljust(32, b"\0") + bytes([0x21, 0xA1, 0x9C, 0x4F, 0xF2, 0x63, 0x54, 0x37,
                                                              0x01, 0x02, 0x0B, 0, 0, 0, 0, 0])
g = ModelGolem()
res = run("sbi c:/sbi/brass.sbi 5", files={"c:/sbi/brass.sbi": sbi}, golem=g)
check(g.instr[5] == sbi_record(sbi, 0), f"sbi: program 5 is the instrument ({[hex(x) for x in g.instr[5][:16]]})")
check(res["lines"] == ["Brass 1: OK"], f"sbi: {res['lines']}")
clean(res, "sbi")

g = ModelGolem()
g.instr[0x2000 | 0x24] = [0] * 128                  # percussion bank 0, note 36
res = run('sbi "c:/sbi/kick.sbi" drum 24', files={"c:/sbi/kick.sbi": sbi}, golem=g)
check(g.instr[0x2000 | 0x24] == sbi_record(sbi, 0x24), "sbi drum: note 36 of percussion bank 0, key 36")
clean(res, "sbi drum")

res = run("sbi c:/x.sbi 5", files={"c:/x.sbi": b"NOT AN SBI FILE".ljust(60, b"\0")})
report = bytes(res["mem"][res["r"][su.H] * 256 + res["r"][su.L]:][:40])
check(res["r"][su.F] & 1 and report.startswith(b"GPARAM: not a 2-operator"), f"not an SBI: {report[:30]}")
clean(res, "not an SBI")
for line in ("sbi c:/x.sbi", "sbi c:/x.sbi 80", "sbi c:/x.sbi drum", "sbi c:/x.sbi drums 3"):
    res = run(line, files={"c:/x.sbi": sbi})
    report = bytes(res["mem"][res["r"][su.H] * 256 + res["r"][su.L]:][:12])
    check(res["r"][su.F] & 1 and report.startswith(b".gparam"), f"'{line}': usage")
sys.exit(1 if fails else 0)
