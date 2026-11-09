"""Checks the sound-parameter client library (src/lib/gparam.s) in a Z80 simulator.

A model of GOLEM.DRV's WRITE (takes 1-16 bytes per call, at random, fixed
seeds) and READ (up to 16 of the bytes that have arrived) connects the library to a Golem. By default the Golem is a model of the
protocol in this file, written from docs/sound-params.md and the firmware's
src/golem/params.cpp; with --golemd it is a real golemd on a pseudo-terminal
(golem-linux), the same protocol code as the firmware.

Checks: GET_INFO pages 0 and 1, PARAM_WRITE with and without confirmation,
PARAM_READ, a refused write with its error code and position, a byte above
127, a request while another is in progress, a time out, a WOPL file uploaded
from 8K banks (starting mid-bank, so it crosses a bank boundary) and
downloaded into others, a file larger than the room given, and the client
that reads the UART itself (gp_feed) and the one that sends through another
pump (gp_set_sender, as GSEQ's queue). With GP_MAX_DATA 64 and 256.

    python3 tools/ci/test_gparam.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
    python3 tools/ci/test_gparam.py ... --golemd /path/to/golemd
"""
import argparse, os, random, re, select, subprocess, sys, tempfile, time
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--skoolkit", default="/tmp/skoolkit")
ap.add_argument("--golemd", help="a golemd binary: test against it instead of the model")
ap.add_argument("--sizes", default="64,256", help="GP_MAX_DATA values to test")
ap.add_argument("--seeds", default="1,2")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()
sys.path.insert(0, args.skoolkit)
from skoolkit.simulator import Simulator
from skoolkit import simutils as su

RET = 0x7000
IO = 0xE000          # 16-byte driver buffer
REQ = 0xE100         # request or file block
DATA = 0xE200        # write source
DEST = 0xE400        # read destination (256 + guard)
TABLE = 0xE700       # bank table
WINDOW_SLOT = 0x56   # MMU6: $C000-$DFFF
WINDOW = 0xC000


def build(max_data):
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "test.s").write_text(
            f"        org $8000\nGP_MAX_DATA equ {max_data}\n"
            f'        include "{args.repo}/include/mt32_api.inc"\n'
            f'        include "{args.repo}/src/lib/gparam.s"\n'
            # The other pump: takes a message (DE > 0) or answers whether the
            # last one has gone (DE = 0); never busy, logs into $E900...
            "sender: ld a,d\n        or e\n        ret z\n"
            "        ld (sender_hl),hl\n        ld (sender_de),de\n        or a\n        ret\n"
            "sender_hl: dw 0\nsender_de: dw 0\n")
        subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", "--raw=o.bin", "--sym=o.sym", "test.s"],
                       cwd=t, check=True, capture_output=True)
        img = (t / "o.bin").read_bytes()
        sym = {}
        for line in (t / "o.sym").read_text().splitlines():
            m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", line)
            if m:
                sym[m.group(1).lower()] = int(m.group(2), 16)
    return img, sym


# --- the Golem ---------------------------------------------------------------

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gparam_model import HEADER, ModelGolem, checksum, pack, unpack  # noqa: E402


class GolemdGolem:
    """A real golemd on a pseudo-terminal."""

    def __init__(self, path):
        import pty
        self.tmp = tempfile.TemporaryDirectory()
        self.master, slave = pty.openpty()
        conf = Path(self.tmp.name) / "golem.conf"
        # Bank 0 (17K as WOPL): DMXOPL3, the default, is 116K and takes long here
        conf.write_text("[audio]\ndevice = null\nrealtime = off\n[system]\ndefault_synth = opl3\n"
                        f"data_dir = {self.tmp.name}\n[midi]\nusb = off\n[opl3]\nbank = 0\n")
        self.proc = subprocess.Popen([path, "-c", str(conf), "-s", os.ttyname(slave), "-n"],
                                     stderr=subprocess.PIPE, text=True)
        log, end = "", time.time() + 10
        while time.time() < end:
            line = self.proc.stderr.readline()
            log += line
            if "golemd ready" in line or self.proc.poll() is not None:
                break
        assert "golemd ready" in log, log
        self.out = bytearray()
        self.frames = []
        self.silent = False

    def receive(self, data):
        if not self.silent:
            os.write(self.master, bytes(data))

    def pump(self, wait=0.002):
        r, _, _ = select.select([self.master], [], [], wait)
        if r:
            self.out += os.read(self.master, 4096)

    def take(self, n):
        self.pump(0)
        data = self.out[:n]
        del self.out[:n]
        return data

    def close(self):
        self.proc.terminate()
        self.proc.wait(timeout=5)


# --- the Next ----------------------------------------------------------------

class Next:
    def __init__(self, img, sym, golem, seed):
        self.mem = [0] * 65536
        self.mem[0x8000:0x8000 + len(img)] = list(img)
        self.mem[0x0008] = 0xC9
        self.sym, self.golem, self.rng = sym, golem, random.Random(seed)
        self.banks = {b: bytearray(8192) for b in range(20, 40)}
        self.nr, self.sel = {WINDOW_SLOT: 0}, [0]
        self.writes = self.reads = 0
        self.ix_ok = True
        self.feed_all = False
        nxt = self

        class Ports:
            def read_port(self, regs, port):
                if port == 0x243B: return nxt.sel[0]
                if port == 0x253B: return nxt.nr.get(nxt.sel[0], 0)
                return 0xFF

            def write_port(self, regs, port, value, t=0):
                if port == 0x243B:
                    nxt.sel[0] = value
                elif port == 0x253B:
                    if nxt.sel[0] == WINDOW_SLOT:
                        nxt.page(value)
                    nxt.nr[nxt.sel[0]] = value

        self.sim = Simulator(self.mem)
        self.sim.set_tracer(Ports())
        self.r = self.sim.registers

    def page(self, bank):
        old = self.nr[WINDOW_SLOT]
        if old in self.banks:
            self.banks[old][:] = bytes(self.mem[WINDOW:WINDOW + 8192])
        self.mem[WINDOW:WINDOW + 8192] = list(self.banks.get(bank, bytes(8192)))

    def flush_window(self):
        self.page(self.nr[WINDOW_SLOT])

    def driver(self):
        r, mem = self.r, self.mem
        sp = r[su.SP]
        ret = mem[sp] + 256 * mem[sp + 1]
        assert mem[ret] == 0x92, "M_DRVAPI expected"
        ret += 1
        mem[sp], mem[sp + 1] = ret & 255, ret >> 8
        hl, de = r[su.H] * 256 + r[su.L], r[su.D] * 256 + r[su.E]
        ix = r[su.IXh] * 256 + r[su.IXl]
        assert r[su.C] == 0x2D
        if ix != hl:
            self.ix_ok = False
        assert hl >= 0x4000
        if r[su.B] == 2:      # WRITE
            self.writes += 1
            n = min(de, 16, self.rng.randint(1, 16))
            self.golem.receive(mem[hl:hl + n])
        elif r[su.B] == 6:    # READ
            self.reads += 1
            data = self.golem.take(min(de, 16))     # what has arrived, up to 16
            n = len(data)
            mem[hl:hl + n] = list(data)
        else:
            raise AssertionError(f"driver function {r[su.B]}")
        r[su.B], r[su.C] = 0, n
        r[su.F] &= ~1

    def call(self, name, **regs):
        r, mem = self.r, self.mem
        for k, v in regs.items():
            if k in ("HL", "DE", "BC"):
                r[getattr(su, k[0])], r[getattr(su, k[1])] = v >> 8, v & 255
            else:
                r[getattr(su, k)] = v
        r[su.IXh], r[su.IXl] = 0x12, 0x34
        r[su.SP] = 0xF000 - 2
        mem[0xEFFE], mem[0xEFFF] = RET & 255, RET >> 8
        r[su.PC] = self.sym[name]
        steps = 0
        while r[su.PC] != RET:
            if r[su.PC] == 0x0008:
                self.driver()
            self.sim.run()
            steps += 1
            if steps > 2_000_000:
                raise RuntimeError(f"{name}: no return")
        assert r[su.IXh] == 0x12 and r[su.IXl] == 0x34, f"{name} did not keep IX"
        return r[su.A], r[su.F] & 1

    def update(self, budget=4):
        if self.feed_all:
            for b in self.golem.take(64):
                self.call("gp_feed", A=b)
        a, _ = self.call("gp_update", B=budget)
        if hasattr(self.golem, "pump"):
            self.golem.pump(0.001)
        return a

    def run(self, frames=4000):
        for n in range(frames):
            a = self.update()
            if a != 1:
                return a, n
        return a, frames

    def result(self):
        self.call("gp_result")
        r = self.r
        return r[su.A], r[su.B], r[su.D] * 256 + r[su.E], r[su.C] << 16 | r[su.H] * 256 + r[su.L]

    def req(self, area, address, data_at, length, flags=0):
        m = self.mem
        m[REQ:REQ + 9] = [area, address & 255, (address >> 8) & 255, address >> 16,
                          data_at & 255, data_at >> 8, length & 255, length >> 8, flags]

    def file_block(self, size, banks, offset):
        m = self.mem
        m[TABLE] = len(banks)
        m[TABLE + 1:TABLE + 1 + len(banks)] = banks
        m[REQ:REQ + 10] = [1, 0, size & 255, (size >> 8) & 255, size >> 16, TABLE & 255, TABLE >> 8,
                           offset & 255, offset >> 8, WINDOW_SLOT]


fails = 0


def check(ok, text):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {text}")


def suite(max_data, seed):
    img, sym = build(max_data)
    golem = GolemdGolem(args.golemd) if args.golemd else ModelGolem()
    big = not args.golemd and max_data == 256 and seed == 1
    if big:                                            # beyond 64K: 24-bit sizes
        golem.blob = bytes(b"WOPL3-BANK\0" + bytes((i * 13 + (i >> 9)) & 255 for i in range(70000 - 11)))
    nx = Next(img, sym, golem, seed)
    tag = f"[max {max_data}, seed {seed}]"
    nx.call("gp_init", HL=IO)

    # GET_INFO page 0 and 1
    a, c = nx.call("gp_info", A=0, HL=DEST, B=40)
    st, n = nx.run()
    s, err, det, cnt = nx.result()
    page0 = nx.mem[DEST:DEST + cnt]
    check(not c and st == 2 and cnt >= 20 and page0[:2] == [1, 1], f"{tag} GET_INFO page 0: {st} {err:02x} {page0[:4]}")
    nx.call("gp_info", A=1, HL=DEST, B=40)
    st, _ = nx.run()
    s, err, det, cnt = nx.result()
    name = bytes(nx.mem[DEST:DEST + cnt]).decode("latin1")
    check(st == 2 and cnt > 3, f"{tag} GET_INFO page 1: {name!r}")
    nx.call("gp_info", A=1, HL=DEST, B=3)
    nx.run()
    check(nx.result()[3] == 3 and bytes(nx.mem[DEST:DEST + 3]).decode() == name[:3], f"{tag} page cut to the room given")

    # PARAM_WRITE confirmed, then read back (area 10 section 00: USB in thru,
    # keys to the Next)
    nx.mem[DATA:DATA + 2] = [1, 0]
    nx.req(0x10, 0x03, DATA, 2, 1)
    a, c = nx.call("gp_write", HL=REQ)
    st, _ = nx.run()
    check(not c and st == 2 and nx.result()[3] == 2, f"{tag} PARAM_WRITE confirmed: {nx.result()}")
    nx.req(0x10, 0x03, DEST, 2)
    nx.call("gp_read", HL=REQ)
    st, _ = nx.run()
    check(st == 2 and nx.mem[DEST:DEST + 2] == [1, 0], f"{tag} PARAM_READ: {nx.mem[DEST:DEST + 2]}")

    # Unconfirmed: done once sent, and the Golem got it
    nx.mem[DATA] = 60
    nx.req(0x10, 0x00, DATA, 1)
    nx.call("gp_write", HL=REQ)
    st, frames = nx.run()
    for _ in range(5):
        nx.update()
    nx.req(0x10, 0x00, DEST, 1)
    nx.call("gp_read", HL=REQ)
    nx.run()
    check(st == 2 and nx.mem[DEST] == 60, f"{tag} unconfirmed write: {st}, then {nx.mem[DEST]}")

    # A refused value: the Golem's code and position (volume 0-100, then the
    # loudness switch 0/1)
    nx.mem[DATA:DATA + 2] = [1, 101]
    nx.req(0x10, 0x05, DATA, 2, 1)
    nx.call("gp_write", HL=REQ)
    st, _ = nx.run()
    s, err, det, cnt = nx.result()
    check(st == 3 and err == 0x04 and det == 1, f"{tag} refused value: state {st}, error {err:02x}, position {det}")

    # A byte above 127 never leaves
    nx.mem[DATA:DATA + 2] = [1, 0x80]
    nx.req(0x10, 0x00, DATA, 2, 1)
    a, c = nx.call("gp_write", HL=REQ)
    check(c and a == 0x25, f"{tag} byte above 127 refused: {a:02x} {c}")

    # Length 0 or above GP_MAX_DATA
    nx.req(0x01, 0, DEST, max_data + 1)
    a, c = nx.call("gp_read", HL=REQ)
    check(c and a == 0x22, f"{tag} length above GP_MAX_DATA refused")

    # Busy: a second request while one is in progress
    nx.req(0x01, 0x80, DEST, 64)
    nx.call("gp_read", HL=REQ)
    a, c = nx.call("gp_read", HL=REQ)
    check(c and a == 0x23, f"{tag} second request while busy refused")
    st, _ = nx.run()
    check(st == 2 and nx.result()[3] == 64, f"{tag} the first one still finishes")

    # A long read: one instrument record
    if not args.golemd:
        nx.req(0x01, 5 << 7, DEST, min(128, max_data))
        nx.call("gp_read", HL=REQ)
        st, _ = nx.run()
        want = golem.instr[5][:min(128, max_data)]
        check(st == 2 and nx.mem[DEST:DEST + len(want)] == want, f"{tag} instrument record read")
    else:
        nx.req(0x01, 0, DEST, min(128, max_data))
        nx.call("gp_read", HL=REQ)
        st, _ = nx.run()
        check(st == 2, f"{tag} instrument record read from golemd")
        rec = nx.mem[DEST:DEST + min(128, max_data)]
        nx.mem[DATA] = 63
        nx.req(0x01, 0x26, DATA, 1, 1)                 # operator 1 total level
        nx.call("gp_write", HL=REQ)
        st, _ = nx.run()
        nx.req(0x01, 0x26, DEST, 1)
        nx.call("gp_read", HL=REQ)
        nx.run()
        check(st == 2 and nx.mem[DEST] == 63, f"{tag} instrument byte written in golemd ({rec[0x26]} -> 63)")
        nx.mem[DATA] = 16
        nx.req(0x01, 0x27, DATA, 1, 1)                 # attack 0-15
        nx.call("gp_write", HL=REQ)
        st, _ = nx.run()
        s, err, det, _ = nx.result()
        check(st == 3 and err == 0x04 and det == 0, f"{tag} golemd refuses attack 16: {err:02x} at {det}")

    # Time out: the Golem does not answer
    golem.silent = True
    nx.req(0x10, 0, DEST, 1)
    nx.call("gp_read", HL=REQ)
    st, frames = nx.run()
    golem.silent = False
    s, err, _, _ = nx.result()
    check(st == 3 and err == 0x20 and 20 <= frames <= 40, f"{tag} time out after {frames} frames: {err:02x}")
    for _ in range(10):
        nx.update()
        golem.take(1000)

    # BLOB: download into banks (offset 8000: crosses into the second bank)
    nx.file_block(10 * 8192 - 8000, list(range(20, 30)), 8000)
    nx.call("gp_blob_get", HL=REQ)
    st, frames = nx.run(20000)
    s, err, det, size = nx.result()
    nx.flush_window()
    flat = b"".join(bytes(nx.banks[b]) for b in range(20, 30))[8000:8000 + size]
    if args.golemd:
        ok = st == 2 and flat[:11] == b"WOPL3-BANK\0" and size > 1000
    else:
        ok = st == 2 and flat == golem.blob
    check(ok, f"{tag} BLOB download: state {st} error {err:02x}, {size} bytes in {frames} frames")
    if big:
        check(size == 70000, f"{tag} a file over 64K: {size} bytes")
    original = flat

    # BLOB: upload it back with a change, from other banks (offset 8100)
    changed = bytearray(original)
    if args.golemd:
        melodic, percussive = changed[13] << 8 | changed[14], changed[15] << 8 | changed[16]
        first = 19 + 34 * (melodic + percussive)
        changed[first:first + 10] = b"From Next!"
    else:
        changed[500] ^= 0x55
    image = bytes(8100) + bytes(changed)
    for i, b in enumerate(range(30, 40)):
        nx.banks[b][:] = image[i * 8192:(i + 1) * 8192].ljust(8192, b"\0")
    nx.nr[WINDOW_SLOT] = 0
    nx.mem[WINDOW:WINDOW + 8192] = [0] * 8192
    nx.file_block(len(changed), list(range(30, 40)), 8100)
    nx.call("gp_blob_put", HL=REQ)
    st, frames = nx.run(30000)
    s, err, det, done = nx.result()
    check(st == 2 and done == len(changed), f"{tag} BLOB upload: state {st} error {err:02x}, {done} bytes, {frames} frames")
    if not args.golemd:
        check(golem.blob == bytes(changed), f"{tag} the Golem got the file")
    else:
        nx.req(0x01, 0x60, DEST, 10)                   # name of program 0
        nx.call("gp_read", HL=REQ)
        nx.run()
        check(bytes(nx.mem[DEST:DEST + 10]) == b"From Next!", f"{tag} golemd plays the uploaded bank")
    check(nx.nr[WINDOW_SLOT] == 0, f"{tag} MMU slot restored")

    # Room too small for the file
    nx.file_block(100, [20], 0)
    nx.call("gp_blob_get", HL=REQ)
    st, _ = nx.run()
    check(st == 3 and nx.result()[1] == 0x22, f"{tag} file larger than the room: {nx.result()[1]:02x}")

    # The client reads the UART itself and feeds the bytes
    nx.call("gp_set_sender", HL=0, A=1)
    nx.feed_all = True
    reads = nx.reads
    nx.req(0x10, 0, DEST, 2)
    nx.call("gp_read", HL=REQ)
    st, _ = nx.run()
    check(st == 2 and nx.reads == reads, f"{tag} gp_feed: done without READs of its own")
    nx.feed_all = False

    # Another pump sends (GSEQ's queue): the library hands it the frame
    nx.call("gp_set_sender", HL=sym["sender"], A=0)
    writes = nx.writes
    nx.mem[DATA] = 7
    nx.req(0x10, 3, DATA, 1)
    nx.call("gp_write", HL=REQ)
    st, _ = nx.run()
    hl = nx.mem[sym["sender_hl"]] + 256 * nx.mem[sym["sender_hl"] + 1]
    de = nx.mem[sym["sender_de"]] + 256 * nx.mem[sym["sender_de"] + 1]
    frame = nx.mem[hl:hl + de]
    check(st == 2 and nx.writes == writes and frame[:8] == HEADER + [frame[6], 0x08] and frame[-1] == 0xF7
          and (sum(frame[8:-1]) & 0x7F) == 0, f"{tag} sender hook: one whole frame of {de} bytes, no WRITE")

    check(nx.ix_ok, f"{tag} IX = HL on every driver call (programs)")
    if args.golemd:
        golem.close()


for max_data in map(int, args.sizes.split(",")):
    for seed in map(int, args.seeds.split(",")):
        suite(max_data, seed)
sys.exit(1 if fails else 0)
