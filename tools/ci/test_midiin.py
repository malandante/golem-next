"""Checks the MIDI input library (src/lib/midiin.s) in a Z80 simulator.

A model of GOLEM.DRV's READ hands the library a byte stream in chunks of 1-16
bytes (fixed seeds, so every run is the same). mi_get is called until the
stream is exhausted and the messages it returns must match a reference parser:
running status, real-time bytes inside messages, system common messages,
SysEx kept whole or cut at the buffer size, SysEx interrupted by a status byte,
stray data bytes and the Golem replies, which are dropped. Also: one READ per
call at most, and a driver error comes back with carry and its code.

    python3 tools/ci/test_midiin.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, random, re, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
from skoolkit.simulator import Simulator
from skoolkit import simutils as su

RET = 0x7000
RX = 0xC000
SYSEX = 0xC100

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    (t / "test.s").write_text(
        f'        org $8000\n        include "{args.repo}/include/mt32_api.inc"\n'
        f'        include "{args.repo}/src/lib/midiin.s"\n')
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "--sym=o.sym", "test.s"],
                   cwd=t, check=True, capture_output=True)
    img = (t / "o.bin").read_bytes()
    sym = {}
    for line in (t / "o.sym").read_text().splitlines():
        m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", line)
        if m: sym[m.group(1).lower()] = int(m.group(2), 16)


def reference(stream, size):
    """What the library must return, from a straightforward MIDI parser."""
    out, status, need, data, sysex, common = [], 0, 0, [], None, False
    for b in stream:
        if b >= 0xF8:
            out.append(("short", bytes([b])))
        elif b == 0xF0:
            sysex, status, common = [0xF0], 0, False
        elif b == 0xF7:
            if sysex is not None:
                sysex.append(0xF7)
                if not (len(sysex) >= 6 and sysex[1:5] == [0x7D, 0x47, 0x4C, 0x4D]):
                    out.append(("sysex", bytes(sysex[:size]), int(len(sysex) > size)))
                sysex = None
        elif b >= 0x80:
            sysex, data, common = None, [], False
            if b < 0xF0:
                status, need = b, 1 if b & 0xE0 == 0xC0 else 2
            elif b == 0xF6:
                status = 0
                out.append(("short", bytes([b])))
            elif b in (0xF1, 0xF2, 0xF3):
                status, need, common = b, 2 if b == 0xF2 else 1, True
            else:
                status = 0
        elif sysex is not None:
            sysex.append(b)
        elif status:
            data.append(b)
            if len(data) == need:
                out.append(("short", bytes([status] + data)))
                data = []
                if common:
                    status, common = 0, False
    return out


def run(stream, size, seed, error_at=None):
    mem = [0] * 65536
    mem[0x8000:0x8000 + len(img)] = list(img)
    mem[0x0008] = 0xC9
    sim = Simulator(mem)
    r = sim.registers
    rng = random.Random(seed)
    pending = list(stream)
    reads = [0]

    def call(entry, regs=None):
        for k, v in (regs or {}).items(): r[k] = v
        r[su.SP] = 0xF000 - 2; mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
        r[su.PC] = entry
        steps = 0
        while r[su.PC] != RET:
            if r[su.PC] == 0x0008:
                sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1] + 1
                mem[sp], mem[sp + 1] = ret & 255, ret >> 8
                assert r[su.B] == 6 and r[su.C] == 0x2D, "only READ is expected"
                reads[0] += 1
                if error_at is not None and reads[0] == error_at:
                    r[su.A] = 2; r[su.F] |= 1
                else:
                    hl = r[su.H] * 256 + r[su.L]; de = r[su.D] * 256 + r[su.E]
                    n = min(de, rng.randint(1, 16), len(pending))
                    mem[hl:hl + n] = pending[:n]; del pending[:n]
                    r[su.B], r[su.C] = 0, n
                    r[su.F] &= ~1
            sim.run()
            steps += 1
            if steps > 100000:
                raise RuntimeError("no return")
        return r[su.A], r[su.B], r[su.C], r[su.F] & 1

    call(sym["mi_init"], {su.H: RX >> 8, su.L: RX & 255, su.D: SYSEX >> 8, su.E: SYSEX & 255, su.B: size})
    got, idle, max_reads = [], 0, 0
    while idle < 3:
        before = reads[0]
        a, b, c, carry = call(sym["mi_get"])
        max_reads = max(max_reads, reads[0] - before)
        if carry:
            got.append(("error", a))
            continue
        if a == 0:
            idle += 0 if pending else 1
        elif a == 1:
            m = sym["mi_message"]
            got.append(("short", bytes(mem[m:m + b])))
        elif a == 2:
            got.append(("sysex", bytes(mem[SYSEX:SYSEX + b]), c))
        else:
            got.append(("bad", a))
    return got, max_reads


GOLEM_READY = bytes.fromhex("F0 7D 47 4C 4D 01 12 41 05 00 50 F7")
ROLAND = bytes.fromhex("F0 41 10 16 12 10 00 16 50 0A F7")
LONG = bytes([0xF0, 0x43] + list(range(30)) + [0xF7])
CASES = {
    "notes with full status": bytes.fromhex("90 3C 64 80 3C 00 B0 07 64"),
    "running status": bytes.fromhex("90 3C 64 3E 64 40 00 C0 05 06 07"),
    "real time inside a message": bytes.fromhex("90 F8 3C FE 64 F8 E0 00 FA 40"),
    "SysEx kept whole": ROLAND + bytes.fromhex("90 3C 64"),
    "Golem replies dropped": GOLEM_READY + bytes.fromhex("90 3C 64") + GOLEM_READY + ROLAND,
    "SysEx cut at the buffer size": LONG + bytes.fromhex("80 3C 00"),
    "SysEx interrupted by a status": bytes.fromhex("F0 41 10 90 3C 64 F7 3E 64"),
    "system common": bytes.fromhex("F2 10 20 3C F1 05 F6 F3 02 90 3C 64 F4 3C F5 F7 3E"),
    "stray data first": bytes.fromhex("3C 64 F7 90 3C 64"),
    "real time inside SysEx": bytes.fromhex("F0 41 F8 10 F7"),
}

fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


for name, stream in CASES.items():
    for size in (64, 8):
        for seed in (1, 2, 3):
            got, max_reads = run(stream, size, seed)
            want = reference(stream, size)
            check(got == want and max_reads <= 1,
                  f"{name}, SysEx buffer {size}, seed {seed}" + ("" if got == want else f": got {got}, want {want}"))

got, _ = run(bytes.fromhex("90 3C 64 80 3C 00"), 64, 1, error_at=1)
check(got and got[0] == ("error", 2), f"driver error returned with carry: {got[:1]}")

sys.exit(1 if fails else 0)
