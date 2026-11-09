"""Checks the layout of .GOLEM's private work bank ($6000-$7FFF, mapped at
MMU3): the I/O buffer, the bank list, the track states and the local stack
must not overlap. The bank list once started 16 bytes after the buffer, and
the 17-byte reset sent before every song overwrote the first file bank: every
play then failed with "invalid SMF event" (#136, found on the Next).

    python3 tools/ci/check_golem_layout.py --sjasmplus /tmp/sjasmplus/sjasmplus
"""
import argparse, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--sjasmplus", default="sjasmplus")
ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent.parent)
args = ap.parse_args()

fails = 0


def check(ok, what):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}: {what}")


with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    shutil.copytree(args.repo / "src", t / "src"); shutil.copytree(args.repo / "include", t / "include")
    for f in (t / "src").rglob("*.s"):
        f.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", f.read_text()))
    sources = "".join(f.read_text() for f in [t / "src/dot/golem_cli.s", *sorted((t / "src/dot/golem").glob("*.s"))])
    for name in ("golem", "mt32", "gm", "opl3"):
        subprocess.run([args.sjasmplus, "--zxnext", "--nologo", "--msg=war", f"--raw={name}.bin",
                        f"--sym={name}.sym", f"{name}.s"], cwd=t / "src/dot", check=True, capture_output=True)
        sym = {}
        for line in (t / f"src/dot/{name}.sym").read_text().splitlines():
            m = re.match(r"(\w+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
            if m:
                sym[m.group(1)] = int(m.group(2), 16)
        # The longest write into the buffer: offsets used, the reset, a READ,
        # a SysEx chunk
        offsets = [int(n) for n in re.findall(r"IO_BUFFER\+(\d+)\)", sources)]
        longest = max(max(offsets) + 1, sym["RESET_MESSAGES_LENGTH"], sym["MT32_MAX_READ"], 16)
        check(sym["file_banks"] - sym["IO_BUFFER"] >= longest,
              f"{name}: I/O buffer ({longest} bytes at most) before the bank list "
              f"(${sym['IO_BUFFER']:04X}-${sym['file_banks']:04X})")
        check(sym["track_states"] >= sym["file_banks"] + sym["MAX_FILE_BANKS"],
              f"{name}: bank list ({sym['MAX_FILE_BANKS']}) before the track states")
        end = sym["track_states"] + sym["MAX_TRACKS"] * sym["ST_SIZE"]
        check(end <= sym["LOCAL_STACK"] - 1024, f"{name}: track states end at ${end:04X}, 1K of stack below "
              f"${sym['LOCAL_STACK']:04X}")
sys.exit(1 if fails else 0)
