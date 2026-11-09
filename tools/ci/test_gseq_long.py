"""Checks GSEQ's long messages (gs_send_long, src/lib/gseq.s) in a Z80 simulator.

A song of dense notes on three channels with a 60-byte SysEx in the middle
plays through gs_pump, once per 20 ms frame with a budget of 4, into a model
of GOLEM.DRV WRITE that takes up to 16 bytes, as many as a 64-byte UART
FIFO emptying at 31250 baud has room for. Golem frames of 300 and
62 bytes are queued with gs_send_long while it plays, at moments that land
inside the music's SysEx too. Checks that each long message leaves exactly
once and whole, with no byte of anything else inside it; that the music's
SysEx is never cut either; that without the long messages the music leaves
byte for byte as in a run where none were sent; that a second gs_send_long
while one is pending is refused and DE = 0 answers whether it has gone; and
that gs_query reports busy until the last byte. Last, the gp_* library
(src/lib/gparam.s) sends through GSEQ (gp_set_sender with gs_send_long) while
the song plays, to the Golem model of gparam_model.py: a confirmed write, a
read and a 1035-byte bank download, with the music unchanged.

    python3 tools/ci/test_gseq_long.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, json, random, re, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
sys.path.insert(0, str(args.repo / "tools/host"))
from skoolkit.simulator import Simulator
from skoolkit import simutils as su
import gseq
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gparam_model import HEADER, ModelGolem

RET = 0x7000
IO = 0xE000
TABLE = 0xE100
LONG = 0xE200          # the long messages live here, $200 apart (outside the window)
WINDOW_SLOT = 0x56     # MMU6: $C000-$DFFF
WINDOW = 0xC000
FIFO = 64              # bytes the UART holds
DRAIN = 62             # 31250 baud: 62.5 bytes leave per 20 ms frame

# The song: notes every 10 ms on channels 1-3 for 1.6 s, a SysEx at 600 ms
messages = []
for i in range(160):
    ms = i * 10
    ch = i % 3
    messages.append({"ms": ms, "bytes": f"{0x90 | ch:02x} {40 + i % 40:02x} 64"})
    if i >= 3:
        messages.append({"ms": ms, "bytes": f"{0x80 | ((i - 3) % 3):02x} {40 + (i - 3) % 40:02x} 00"})
sysex = "f0 41 10 16 12 " + " ".join(f"{(i * 5) & 0x7f:02x}" for i in range(54)) + " 00 f7"
messages.append({"ms": 600, "bytes": sysex})
messages.sort(key=lambda m: m["ms"])
song, _ = gseq.convert(json.dumps({"messages": messages, "end_ms": 1700}).encode(), is_json=True)
SYSEX = bytes.fromhex(sysex)

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    (t / "test.s").write_text(f"        org $8000\nGP_MAX_DATA equ 64\n"
                              f'        include "{args.repo}/include/mt32_api.inc"\n'
                              f'        include "{args.repo}/src/lib/gseq.s"\n'
                              f'        include "{args.repo}/src/lib/gparam.s"\n')
    subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "--sym=o.sym", "test.s"],
                   cwd=t, check=True, capture_output=True)
    img = (t / "o.bin").read_bytes()
    sym = {}
    for line in (t / "o.sym").read_text().splitlines():
        m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", line)
        if m:
            sym[m.group(1).lower()] = int(m.group(2), 16)


def golem_frame(n, seed):
    rng = random.Random(seed)
    body = [rng.randrange(128) for _ in range(n - 10)]
    return bytes([0xF0, 0x7D, 0x47, 0x4C, 0x4D, 0x01, seed & 0x7F, 0x0C] + body + [0xF7])


def run(longs, seed=1, jittery=False, golem=None, script=None):
    """longs: {frame number: message}. Returns the bytes out and notes.
    golem: a ModelGolem fed with what leaves and answering through READ;
    script(frame, call): called each frame after gs_pump (for gp_*)."""
    mem = [0] * 65536
    mem[0x8000:0x8000 + len(img)] = list(img)
    mem[0x0008] = 0xC9
    banks = {}
    for i in range(0, len(song), 8192):
        banks[30 + i // 8192] = bytearray(song[i:i + 8192].ljust(8192, b"\0"))
    nr, sel, window = {WINDOW_SLOT: 0}, [0], [None]

    def page(bank):
        if window[0] in banks:
            banks[window[0]][:] = bytes(mem[WINDOW:WINDOW + 8192])
        window[0] = bank
        mem[WINDOW:WINDOW + 8192] = list(banks[bank]) if bank in banks else [0] * 8192

    class Ports:
        def read_port(self, regs, port):
            if port == 0x243B: return sel[0]
            if port == 0x253B: return nr.get(sel[0], 0)
            return 0xFF

        def write_port(self, regs, port, value, t=0):
            if port == 0x243B:
                sel[0] = value
            elif port == 0x253B:
                if sel[0] == WINDOW_SLOT:
                    page(value)
                nr[sel[0]] = value

    sim = Simulator(mem); sim.set_tracer(Ports()); r = sim.registers
    out = bytearray()
    fifo = [0]
    rng = random.Random(seed)

    def call(name, **regs):
        for k, v in regs.items():
            if k in ("HL", "DE", "BC"):
                r[getattr(su, k[0])], r[getattr(su, k[1])] = v >> 8, v & 255
            else:
                r[getattr(su, k)] = v
        r[su.SP] = 0xF000 - 2
        mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
        r[su.PC] = sym[name]
        steps = 0
        while r[su.PC] != RET:
            if r[su.PC] == 0x0008:
                sp = r[su.SP]; ret = mem[sp] + 256 * mem[sp + 1]
                assert mem[ret] == 0x92 and r[su.B] in (2, 6)
                ret += 1; mem[sp], mem[sp + 1] = ret & 255, ret >> 8
                hl, de = r[su.H] * 256 + r[su.L], r[su.D] * 256 + r[su.E]
                if r[su.B] == 6:                     # READ: the Golem's replies
                    data = golem.take(min(de, 16)) if golem else b""
                    mem[hl:hl + len(data)] = list(data)
                    r[su.B], r[su.C] = 0, len(data)
                    r[su.F] &= ~1
                    sim.run(); steps += 1
                    continue
                n = min(de, 16, FIFO - fifo[0])     # what the UART has room for
                if jittery:
                    n = min(de, rng.randint(1, 16))
                fifo[0] += n
                out.extend(mem[hl:hl + n])
                if golem:
                    golem.receive(mem[hl:hl + n])
                r[su.B], r[su.C] = 0, n
                r[su.F] &= ~1
            sim.run(); steps += 1
            assert steps < 3_000_000, name
        return r[su.A], r[su.F] & 1

    mem[TABLE] = len(banks)
    mem[TABLE + 1:TABLE + 1 + len(banks)] = list(banks)
    call("gs_init", HL=IO, A=WINDOW_SLOT, DE=0)
    _, c = call("gs_open", HL=TABLE, DE=0)
    assert not c, "gs_open"
    call("gs_start", DE=0)
    notes = {"refused": 0, "asked": [], "busy_at_end": []}
    sent_at = {}
    now = 0
    pending = None
    queued = set()
    for frame in range(400):
        now += 20
        fifo[0] = max(0, fifo[0] - DRAIN)
        due = [f for f in longs if f <= frame and f not in queued]
        if due and not pending:                    # the next one, once the queue is free
            f = min(due)
            msg, at = longs[f], LONG + 0x200 * len(queued)
            mem[at:at + len(msg)] = list(msg)
            _, c = call("gs_send_long", HL=at, DE=len(msg))
            assert not c, f"frame {frame}: queue busy though nothing is pending"
            queued.add(f)
            pending = (f, frame)
            _, c = call("gs_send_long", HL=at, DE=len(msg))
            notes["refused"] += c
        call("gs_pump", DE=now & 0xFFFF, B=4)
        if script:
            script(frame, call, mem, r)
        if pending:
            _, c = call("gs_send_long", HL=LONG, DE=0)
            if not c:
                sent_at[pending[0]] = frame
                notes["asked"].append(frame - pending[1])
                pending = None
    call("gs_query")
    notes["idle"] = not (r[su.F] & 0x40) == 0   # Z set: idle
    notes["sent_at"] = sent_at
    return bytes(out), notes


def split(stream):
    """MIDI byte stream: SysEx as whole frames, channel bytes kept apart."""
    frames, rest, i = [], bytearray(), 0
    while i < len(stream):
        if stream[i] == 0xF0:
            j = stream.index(0xF7, i)
            inner = stream[i + 1:j]
            assert all(b < 0x80 for b in inner), f"a status byte inside a SysEx at {i}"
            frames.append(stream[i:j + 1])
            rest += b"\0"      # where it was
            i = j + 1
        else:
            rest.append(stream[i]); i += 1
    return frames, bytes(rest)


fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


base, _ = run({})
base_frames, base_rest = split(base)
check(SYSEX in base_frames, f"the song's SysEx leaves whole ({len(base)} bytes in all)")

L1, L2, L3 = golem_frame(300, 1), golem_frame(62, 2), golem_frame(300, 3)
# frame 29 is 600 ms: the music's SysEx is due as L1 waits
longs = {5: L1, 29: L2, 30: L3}
stream, notes = run(longs)
frames, rest = split(stream)
for name, msg in (("300-byte", L1), ("62-byte", L2), ("300-byte, queued as the SysEx is due", L3)):
    check(frames.count(msg) == 1, f"{name} long message leaves once and whole")
music = [f for f in frames if f not in (L1, L2, L3)]
check(music == base_frames and SYSEX in music, "the music's SysEx is not cut")
check(rest.replace(b"\0", b"") == base_rest.replace(b"\0", b""), "the music leaves byte for byte as without them")
check(notes["refused"] == 3, f"a second gs_send_long while one is pending is refused ({notes['refused']})")
check(len(notes["asked"]) == 3 and all(0 <= n <= 12 for n in notes["asked"]),
      f"DE = 0 tells when each has gone: after {notes['asked']} frames")
check(notes["idle"], "gs_query idle at the end")

# A driver that takes 1-16 bytes at random: slower, still never mixed
for seed in (2, 3):
    stream, notes = run(longs, seed, jittery=True)
    frames, rest = split(stream)
    whole = all(frames.count(m) == 1 for m in (L1, L2, L3))
    music = [f for f in frames if f not in (L1, L2, L3)]
    check(whole and music == base_frames and rest.replace(b"\0", b"") == base_rest.replace(b"\0", b""),
          f"random WRITE sizes (seed {seed}): whole, once, music unchanged")

# gp_* through GSEQ's queue while the song plays
IO2, REQ, DATA, DEST, FTABLE = 0xE010, 0xEA00, 0xEA20, 0xEA40, 0xEB00
golem = ModelGolem()
log = {"phase": 0, "results": [], "frames": []}


def script(frame, call, mem, r):
    if frame == 0:
        call("gp_init", HL=IO2)
        call("gp_set_sender", HL=sym["gs_send_long"], A=0)
    a, _ = call("gp_update", B=4) if frame else (0, 0)
    if frame > 0 and a == 1:
        return
    if log.get("waiting") and a in (2, 3):
        call("gp_result")
        log["results"].append((a, r[su.B], r[su.C] << 16 | r[su.H] << 8 | r[su.L]))
        log["frames"].append(frame)
        log["waiting"] = False
    phase = log["phase"]
    if frame < 8:
        return
    if phase == 0:                                   # a confirmed write
        mem[DATA:DATA + 3] = [1, 0, 1]
        mem[REQ:REQ + 9] = [0x10, 3, 0, 0, DATA & 255, DATA >> 8, 3, 0, 1]
        call("gp_write", HL=REQ)
    elif phase == 1:                                 # read it back
        mem[REQ:REQ + 9] = [0x10, 3, 0, 0, DEST & 255, DEST >> 8, 3, 0, 0]
        call("gp_read", HL=REQ)
    elif phase == 2:                                 # the bank, into the window's banks
        mem[FTABLE:FTABLE + 3] = [2, 60, 61]
        mem[REQ:REQ + 10] = [1, 0, 0, 0x40, 0, FTABLE & 255, FTABLE >> 8, 0, 0, 0x55]
        call("gp_blob_get", HL=REQ)
    else:
        return
    log["phase"] += 1
    log["waiting"] = True


stream, notes = run(longs, golem=golem, script=script)
frames, rest = split(stream)
music = [f for f in frames if f[:6] != bytes(HEADER) and f not in (L1, L2, L3)]
golem_frames = [f for f in frames if f[:6] == bytes(HEADER) and f not in (L1, L2, L3)]
check([x[:2] for x in log["results"]] == [(2, 0), (2, 0), (2, 0)], f"gp_* done through GSEQ: {log['results']}")
check(len(log["results"]) == 3 and log["results"][2][2] == len(golem.blob), "the 1035-byte bank came back whole")
check(music == base_frames and rest.replace(b"\0", b"") == base_rest.replace(b"\0", b""),
      f"music unchanged with {len(golem_frames)} Golem frames in between")
sys.exit(1 if fails else 0)
