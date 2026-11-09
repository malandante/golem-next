#!/usr/bin/env python3
"""OPL3 instrument banks for the Golem: WOPL files, and .SBI instruments in them.

The Golem's OPL3 engine (libADLMIDI) reads WOPL banks; WOPLX is a WOPL
version 3 file with a "GLMX" block after it (docs/sound-params.md, 7.1),
which this tool keeps untouched. .SBI files are single 2-operator Sound
Blaster instruments: 11 chip registers and a name.

    golembank.py new bank.wopl --name "My bank"
    golembank.py add bank.wopl piano.sbi --program 0
    golembank.py add bank.wopl kick.sbi --drum 36 --key 48
    golembank.py list bank.wopl

The same conversion will exist as a native Next dot command, so the Next does
not need a PC for it.
"""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

MAGIC = b"WOPL3-BANK\0"
LATEST_VERSION = 3
INSTRUMENT_SIZE = {1: 62, 2: 62, 3: 66}
EXTENSION_MAGIC = b"GLMX"

FLAG_4OP = 0x01
FLAG_PSEUDO_4OP = 0x02
FLAG_BLANK = 0x04
FLAG_FIXED_NOTE = 0x40

SBI_MAGIC = b"SBI\x1a"
SBI_SIZE = 52  # magic 4, name 32, registers 16 (11 used)


class BankError(Exception):
    pass


@dataclass
class Operator:
    """One operator's registers: 20, 40, 60, 80 and E0."""

    avekf_20: int = 0
    ksl_l_40: int = 0
    atdec_60: int = 0
    susrel_80: int = 0
    waveform_e0: int = 0

    def pack(self) -> bytes:
        return bytes([self.avekf_20, self.ksl_l_40, self.atdec_60, self.susrel_80, self.waveform_e0])

    @classmethod
    def unpack(cls, data: bytes) -> "Operator":
        return cls(*data[:5])


@dataclass
class Instrument:
    name: str = ""
    note_offset1: int = 0
    note_offset2: int = 0
    velocity_offset: int = 0
    second_voice_detune: int = 0
    percussion_key: int = 0
    flags: int = FLAG_BLANK
    fb_conn1: int = 0
    fb_conn2: int = 0
    # WOPL order: carrier and modulator of the first voice, then the second
    operators: list[Operator] = field(default_factory=lambda: [Operator() for _ in range(4)])
    delay_on_ms: int = 0
    delay_off_ms: int = 0

    @property
    def blank(self) -> bool:
        return bool(self.flags & FLAG_BLANK)

    def pack(self, version: int = LATEST_VERSION) -> bytes:
        name = self.name.encode("ascii", "replace")[:32].ljust(32, b"\0")
        out = name + struct.pack(">hhbbBBBB", self.note_offset1, self.note_offset2, self.velocity_offset,
                                 self.second_voice_detune, self.percussion_key, self.flags, self.fb_conn1,
                                 self.fb_conn2)
        out += b"".join(op.pack() for op in self.operators)
        if version >= 3:
            out += struct.pack(">HH", self.delay_on_ms, self.delay_off_ms)
        return out

    @classmethod
    def unpack(cls, data: bytes, version: int) -> "Instrument":
        name = data[:32].split(b"\0", 1)[0].decode("ascii", "replace")
        (no1, no2, vel, det, key, flags, fb1, fb2) = struct.unpack(">hhbbBBBB", data[32:42])
        ops = [Operator.unpack(data[42 + i * 5:47 + i * 5]) for i in range(4)]
        on = off = 0
        if version >= 3:
            on, off = struct.unpack(">HH", data[62:66])
        return cls(name, no1, no2, vel, det, key, flags, fb1, fb2, ops, on, off)


@dataclass
class Bank:
    name: str = ""
    msb: int = 0
    lsb: int = 0
    instruments: list[Instrument] = field(default_factory=lambda: [Instrument() for _ in range(128)])


@dataclass
class WoplFile:
    opl_flags: int = 0
    volume_model: int = 0
    melodic: list[Bank] = field(default_factory=lambda: [Bank()])
    percussion: list[Bank] = field(default_factory=lambda: [Bank()])
    extension: bytes = b""  # the GLMX block (or anything after the WOPL part), kept as it is


def read_wopl(data: bytes) -> WoplFile:
    if not data.startswith(MAGIC):
        raise BankError("not a WOPL bank (no WOPL3-BANK signature)")
    if len(data) < 19:
        raise BankError("WOPL bank cut short")
    version = struct.unpack_from("<H", data, 11)[0]
    if version not in INSTRUMENT_SIZE:
        raise BankError(f"WOPL version {version} not supported")
    n_mel, n_perc, flags, model = struct.unpack_from(">HHBB", data, 13)
    pos = 19
    bank_meta = []
    if version >= 2:
        for _ in range(n_mel + n_perc):
            if pos + 34 > len(data):
                raise BankError("WOPL bank cut short")
            name = data[pos:pos + 32].split(b"\0", 1)[0].decode("ascii", "replace")
            bank_meta.append((name, data[pos + 33], data[pos + 32]))  # name, msb, lsb
            pos += 34
    else:
        bank_meta = [("", 0, 0)] * (n_mel + n_perc)
    size = INSTRUMENT_SIZE[version]
    banks = []
    for i in range(n_mel + n_perc):
        if pos + 128 * size > len(data):
            raise BankError("WOPL bank cut short")
        name, msb, lsb = bank_meta[i]
        bank = Bank(name, msb, lsb, [Instrument.unpack(data[pos + k * size:pos + (k + 1) * size], version)
                                     for k in range(128)])
        banks.append(bank)
        pos += 128 * size
    return WoplFile(flags, model, banks[:n_mel], banks[n_mel:], bytes(data[pos:]))


def write_wopl(wopl: WoplFile) -> bytes:
    out = bytearray(MAGIC)
    out += struct.pack("<H", LATEST_VERSION)
    out += struct.pack(">HHBB", len(wopl.melodic), len(wopl.percussion), wopl.opl_flags, wopl.volume_model)
    for bank in wopl.melodic + wopl.percussion:
        out += bank.name.encode("ascii", "replace")[:32].ljust(32, b"\0")
        out += bytes([bank.lsb, bank.msb])
    for bank in wopl.melodic + wopl.percussion:
        for ins in bank.instruments:
            out += ins.pack()
    return bytes(out) + wopl.extension


def read_sbi(data: bytes) -> Instrument:
    """A 2-operator .SBI: 11 registers, modulator then carrier for each."""
    if not data.startswith(SBI_MAGIC):
        raise BankError("not an .SBI instrument (no SBI signature; 4-operator variants are not supported yet)")
    if len(data) < 4 + 32 + 11:
        raise BankError(".SBI file cut short")
    name = data[4:36].split(b"\0", 1)[0].decode("ascii", "replace").strip()
    r = data[36:47]
    modulator = Operator(r[0], r[2], r[4], r[6], r[8] & 0x07)
    carrier = Operator(r[1], r[3], r[5], r[7], r[9] & 0x07)
    ins = Instrument(name=name, flags=0, fb_conn1=r[10] & 0x0F)
    ins.operators = [carrier, modulator, Operator(), Operator()]
    return ins


def put_instrument(wopl: WoplFile, ins: Instrument, program: int | None = None, drum: int | None = None,
                   key: int | None = None, bank: int = 0) -> None:
    if (program is None) == (drum is None):
        raise BankError("give either --program or --drum")
    target = wopl.melodic if drum is None else wopl.percussion
    slot = program if drum is None else drum
    if not 0 <= slot <= 127:
        raise BankError("program and drum note go from 0 to 127")
    while len(target) <= bank:
        target.append(Bank(msb=len(target)))
    if drum is not None:
        ins.percussion_key = drum if key is None else key
        if not 0 <= ins.percussion_key <= 127:
            raise BankError("--key goes from 0 to 127")
    target[bank].instruments[slot] = ins


def describe(wopl: WoplFile) -> str:
    lines = [f"{len(wopl.melodic)} melodic and {len(wopl.percussion)} percussion banks"]
    if wopl.extension.startswith(EXTENSION_MAGIC):
        lines.append("WOPLX: Golem extension block present")
    for kind, banks in (("melodic", wopl.melodic), ("percussion", wopl.percussion)):
        for i, bank in enumerate(banks):
            used = [(k, ins) for k, ins in enumerate(bank.instruments) if not ins.blank]
            lines.append(f"{kind} bank {i} (MSB {bank.msb}, LSB {bank.lsb}) {bank.name!r}: {len(used)} instruments")
            for k, ins in used:
                mode = "4-op" if ins.flags & FLAG_4OP and not ins.flags & FLAG_PSEUDO_4OP else (
                    "pseudo 4-op" if ins.flags & FLAG_PSEUDO_4OP else "2-op")
                extra = f", key {ins.percussion_key}" if kind == "percussion" else ""
                lines.append(f"  {k:3d} {ins.name or '(no name)'} [{mode}{extra}]")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="OPL3 banks (WOPL/WOPLX) for the Golem")
    sub = parser.add_subparsers(dest="command", required=True)

    p_new = sub.add_parser("new", help="an empty bank: one melodic and one percussion bank")
    p_new.add_argument("bank", type=Path)
    p_new.add_argument("--name", default="", help="name of the melodic bank")

    p_add = sub.add_parser("add", help="put an .SBI instrument into a bank")
    p_add.add_argument("bank", type=Path)
    p_add.add_argument("sbi", type=Path)
    where = p_add.add_mutually_exclusive_group(required=True)
    where.add_argument("--program", type=int, help="melodic program 0-127")
    where.add_argument("--drum", type=int, help="percussion: the MIDI note on channel 10 (0-127)")
    p_add.add_argument("--key", type=int, help="percussion: the note the drum sounds at (default: --drum)")
    p_add.add_argument("--name", help="instrument name instead of the one in the .SBI")
    p_add.add_argument("--out", type=Path, help="write here instead of changing the bank")

    p_list = sub.add_parser("list", help="what a bank holds")
    p_list.add_argument("bank", type=Path)

    args = parser.parse_args(argv)
    try:
        if args.command == "new":
            if args.bank.exists():
                raise BankError(f"{args.bank} already exists")
            wopl = WoplFile()
            wopl.melodic[0].name = args.name
            args.bank.write_bytes(write_wopl(wopl))
            print(f"{args.bank}: empty bank")
        elif args.command == "add":
            wopl = read_wopl(args.bank.read_bytes())
            ins = read_sbi(args.sbi.read_bytes())
            if args.name is not None:
                ins.name = args.name
            put_instrument(wopl, ins, args.program, args.drum, args.key)
            out = args.out or args.bank
            out.write_bytes(write_wopl(wopl))
            where_ = f"program {args.program}" if args.program is not None else f"drum {args.drum}"
            print(f"{out}: {ins.name or args.sbi.name} as {where_}")
        else:
            print(describe(read_wopl(args.bank.read_bytes())))
    except (BankError, OSError) as error:
        print(f"golembank: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
