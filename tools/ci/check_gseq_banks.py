#!/usr/bin/env python3
"""Build the GSEQ library banks (src/lib/gseq_*.s) with sjasmplus and check
that each fits in 8 KB, carries the signature at offset 27 and starts with
the jump table at its slot address. The product build uses SNasm
(tools/build-gseq-bank.ps1); this keeps the sources assembling in CI."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SLOTS = (0x4000, 0x6000, 0x8000, 0xA000, 0xC000, 0xE000)
ENTRIES = 9


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sjasmplus", default="sjasmplus")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        tree = Path(tmp)
        shutil.copytree(args.repo / "src", tree / "src")
        shutil.copytree(args.repo / "include", tree / "include")
        for path in (tree / "src").rglob("*.s"):
            text = path.read_text()
            path.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", text))
        for slot in SLOTS:
            name = f"gseq_{slot:04x}.s"
            output = tree / f"GSEQ{slot:04X}.BIN"
            subprocess.run(
                [args.sjasmplus, "--zxnext", "--nologo", "--msg=war", f"--raw={output}", name],
                cwd=tree / "src" / "lib",
                check=True,
            )
            data = output.read_bytes()
            problems = []
            if not 0 < len(data) <= 8192:
                problems.append(f"size {len(data)}")
            if data[27:32] != b"GSEQ\x01":
                problems.append("no signature at offset 27")
            for entry in range(ENTRIES):
                op = data[entry * 3]
                target = data[entry * 3 + 1] | data[entry * 3 + 2] << 8
                if op != 0xC3 or not slot <= target < slot + len(data):
                    problems.append(f"entry {entry} is not a JP inside the bank")
            status = "FAIL " + ", ".join(problems) if problems else "ok"
            print(f"{output.name}: {len(data)} bytes {status}")
            failures += bool(problems)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
