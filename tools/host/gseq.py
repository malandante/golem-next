#!/usr/bin/env python3
"""Convert music into GSEQ, the M6 phase 1 sequence format (docs/m6-gseq.md).

Input is a Standard MIDI File (format 0 or 1, PPQN) or a JSON list of timed
MIDI messages, which is what game-specific extractors produce. Output is a
.GSQ file and a report with warnings (cable bandwidth, notes left sounding at
the loop point, SysEx packets that had to be joined or delayed).

The Next only compares deadlines and copies bytes, so everything fixed is
resolved here: tracks are merged, ticks become milliseconds through the tempo
map with exact arithmetic, and every message carries its explicit status.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path

MAGIC = b"GSEQ"
VERSION_MAJOR = 1
VERSION_MINOR = 0
HEADER_SIZE = 32
FLAG_LOOP = 0x0001
TARGETS = {"any": 0, "mt32": 1, "gm": 2}  # header byte 15: synth the music was made for

KIND_CONTROL = 0xFF
KIND_SYSEX = 0xF0
OP_END = 0x00
OP_NOTICE = 0x01
OP_LOOP_START = 0x02

WIRE_BYTES_PER_SECOND = 3125  # 31250 baud, 10 bits per byte
MAX_DELTA = (1 << 28) - 1
MAX_SYSEX = 65535


class GseqError(ValueError):
    """Input that cannot be represented in GSEQ."""


# ---------------------------------------------------------------- data model

@dataclass
class Message:
    """One record before encoding: a MIDI message or a control order."""

    ms: int
    data: bytes = b""          # complete MIDI message (status first), if any
    control: int | None = None  # control order, if this is a control record
    params: bytes = b""

    def wire_length(self) -> int:
        return len(self.data)


@dataclass
class Sequence:
    messages: list[Message]
    end_ms: int
    loop_ms: int | None = None
    warnings: list[str] = field(default_factory=list)
    target: int = 0


# ---------------------------------------------------------------- helpers

def encode_vlq(value: int) -> bytes:
    if value < 0 or value > MAX_DELTA:
        raise GseqError(f"VLQ value out of range: {value}")
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.insert(0, 0x80 | (value & 0x7F))
        value >>= 7
    return bytes(out)


def read_vlq(data: bytes, pos: int, limit: int | None = None) -> tuple[int, int]:
    limit = len(data) if limit is None else limit
    value = 0
    for _ in range(4):
        if pos >= limit:
            raise GseqError("truncated VLQ")
        byte = data[pos]
        pos += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, pos
    raise GseqError("VLQ longer than 4 bytes")


def channel_data_length(status: int) -> int:
    return 1 if status & 0xF0 in (0xC0, 0xD0) else 2


def check_message(data: bytes) -> None:
    """Raise GseqError unless data is one complete, valid MIDI message."""
    if not data:
        raise GseqError("empty message")
    status = data[0]
    if 0x80 <= status <= 0xEF:
        if len(data) != 1 + channel_data_length(status):
            raise GseqError(f"channel message {data.hex(' ')} has the wrong length")
        if any(b & 0x80 for b in data[1:]):
            raise GseqError(f"channel message {data.hex(' ')} has 8-bit data")
    elif status == 0xF0:
        if len(data) < 2 or data[-1] != 0xF7:
            raise GseqError("SysEx does not end with F7")
        if any(b & 0x80 for b in data[1:-1]):
            raise GseqError("SysEx has 8-bit data before F7")
        if len(data) - 1 > MAX_SYSEX:
            raise GseqError("SysEx longer than 65535 bytes")
    else:
        raise GseqError(f"status {status:02X} is not supported in GSEQ v1")


# ---------------------------------------------------------------- SMF input

@dataclass
class _SmfEvent:
    tick: int
    track: int
    order: int
    kind: str           # "midi", "tempo", "marker", "end"
    data: bytes = b""
    tempo: int = 0
    text: str = ""


def _parse_track(chunk: bytes, track: int, warnings: list[str]) -> list[_SmfEvent]:
    events: list[_SmfEvent] = []
    pos, tick, running, order = 0, 0, 0, 0
    pending_sysex: bytearray | None = None  # F0 packet waiting for F7 packets
    pending_tick = 0
    while pos < len(chunk):
        delta, pos = read_vlq(chunk, pos)
        tick += delta
        if pos >= len(chunk):
            raise GseqError(f"track {track}: ends before an event")
        status = chunk[pos]
        if status == 0xFF:
            if pos + 2 > len(chunk):
                raise GseqError(f"track {track}: truncated meta event")
            meta = chunk[pos + 1]
            length, pos = read_vlq(chunk, pos + 2)
            body = chunk[pos:pos + length]
            if len(body) != length:
                raise GseqError(f"track {track}: truncated meta event")
            pos += length
            running = 0
            if meta == 0x51:
                if length != 3:
                    raise GseqError(f"track {track}: tempo event must have 3 bytes")
                value = int.from_bytes(body, "big")
                if value == 0:
                    raise GseqError(f"track {track}: tempo 0")
                events.append(_SmfEvent(tick, track, order, "tempo", tempo=value))
            elif meta == 0x06:
                text = body.decode("latin-1").strip()
                events.append(_SmfEvent(tick, track, order, "marker", text=text))
            elif meta == 0x2F:
                events.append(_SmfEvent(tick, track, order, "end"))
                order += 1
                break
            order += 1
            continue
        if status in (0xF0, 0xF7):
            length, pos = read_vlq(chunk, pos + 1)
            body = chunk[pos:pos + length]
            if len(body) != length:
                raise GseqError(f"track {track}: truncated SysEx")
            pos += length
            running = 0
            if status == 0xF0:
                if pending_sysex is not None:
                    raise GseqError(f"track {track}: new F0 while a SysEx is open")
                message = bytearray(b"\xF0") + body
                if message[-1] == 0xF7:
                    events.append(_SmfEvent(tick, track, order, "midi", bytes(message)))
                    order += 1
                else:
                    pending_sysex, pending_tick = message, tick
            else:
                if pending_sysex is None:
                    raise GseqError(f"track {track}: F7 escape packets are not supported")
                pending_sysex += body
                if pending_sysex[-1] == 0xF7:
                    if tick != pending_tick:
                        warnings.append(
                            f"track {track}: SysEx split over ticks {pending_tick}-{tick} "
                            "joined and sent whole at the first tick")
                    events.append(_SmfEvent(pending_tick, track, order, "midi", bytes(pending_sysex)))
                    order += 1
                    pending_sysex = None
            continue
        if status & 0x80:
            if status > 0xEF:
                raise GseqError(f"track {track}: status {status:02X} is not allowed in an SMF track")
            running = status
            pos += 1
        elif not running:
            raise GseqError(f"track {track}: running status without a previous status")
        size = channel_data_length(running)
        body = chunk[pos:pos + size]
        if len(body) != size:
            raise GseqError(f"track {track}: truncated channel event")
        pos += size
        events.append(_SmfEvent(tick, track, order, "midi", bytes([running]) + body))
        order += 1
    if pending_sysex is not None:
        raise GseqError(f"track {track}: SysEx without its final F7")
    return events


def read_smf(data: bytes, warnings: list[str]) -> tuple[list[_SmfEvent], int]:
    """Return the merged SMF events (tick order, ties by track) and the PPQN."""
    if data[:4] != b"MThd" or len(data) < 14:
        raise GseqError("not a Standard MIDI File")
    header_length, smf_format, tracks, division = struct.unpack(">IHHH", data[4:14])
    if header_length < 6:
        raise GseqError("MThd too short")
    if smf_format not in (0, 1):
        raise GseqError(f"SMF format {smf_format} is not supported (0 or 1)")
    if division & 0x8000 or division == 0:
        raise GseqError("SMPTE or zero division is not supported")
    pos = 8 + header_length
    events: list[_SmfEvent] = []
    track = 0
    while pos + 8 <= len(data) and track < tracks:
        kind = data[pos:pos + 4]
        length = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length:
            raise GseqError("chunk runs past the end of the file")
        pos += 8 + length
        if kind != b"MTrk":
            continue  # unknown chunks are skipped, as the SMF spec asks
        events.extend(_parse_track(body, track, warnings))
        track += 1
    if track != tracks:
        raise GseqError(f"header declares {tracks} tracks, found {track}")
    events.sort(key=lambda e: (e.tick, e.track, e.order))
    return events, division


def smf_to_messages(data: bytes, warnings: list[str]) -> tuple[list[Message], int, dict[str, int]]:
    """Convert to timed messages. Returns messages, end ms and marker times."""
    events, division = read_smf(data, warnings)
    tempo = 500000
    last_tick = 0
    elapsed_us = Fraction(0)
    messages: list[Message] = []
    markers: dict[str, int] = {}
    end_ms = 0

    def to_ms(us: Fraction) -> int:
        return int((us / 1000) + Fraction(1, 2))  # nearest, halves up

    for event in events:
        elapsed_us += Fraction((event.tick - last_tick) * tempo, division)
        last_tick = event.tick
        ms = to_ms(elapsed_us)
        if event.kind == "tempo":
            tempo = event.tempo
        elif event.kind == "midi":
            check_message(event.data)
            messages.append(Message(ms, event.data))
        elif event.kind == "marker":
            key = event.text.lower()
            if key in ("loopstart", "loopend") and key not in markers:
                markers[key] = ms
        end_ms = max(end_ms, ms)
    return messages, end_ms, markers


# ---------------------------------------------------------------- JSON input

def json_to_messages(text: str) -> tuple[list[Message], int, dict[str, int]]:
    """JSON: {"messages": [{"ms": 0, "bytes": "90 3c 64"}, ...],
    optional "end_ms", "loop_start_ms", "loop_end_ms"}."""
    document = json.loads(text)
    messages: list[Message] = []
    previous = 0
    for item in document["messages"]:
        ms = int(item["ms"])
        if ms < previous:
            raise GseqError("JSON messages must be in time order")
        previous = ms
        if "notice" in item:
            messages.append(Message(ms, control=OP_NOTICE, params=bytes([int(item["notice"]) & 0xFF])))
            continue
        data = bytes.fromhex(item["bytes"])
        check_message(data)
        messages.append(Message(ms, data))
    end_ms = int(document.get("end_ms", previous))
    markers = {}
    if "loop_start_ms" in document:
        markers["loopstart"] = int(document["loop_start_ms"])
    if "loop_end_ms" in document:
        markers["loopend"] = int(document["loop_end_ms"])
    return messages, end_ms, markers


# ---------------------------------------------------------------- shaping

def build_sequence(messages: list[Message], end_ms: int, markers: dict[str, int],
                   loop: bool, loop_start_ms: int | None, sysex_gap_ms: int | None) -> Sequence:
    warnings: list[str] = []
    if loop_start_ms is None and "loopstart" in markers:
        loop_start_ms = markers["loopstart"]
    if loop_start_ms is not None:
        loop = True
    if "loopend" in markers and loop:
        loop_end = markers["loopend"]
        dropped = [m for m in messages if m.ms >= loop_end]
        if dropped:
            warnings.append(f"{len(dropped)} messages at or after loopEnd ({loop_end} ms) dropped")
        messages = [m for m in messages if m.ms < loop_end]
        end_ms = loop_end
    if loop and loop_start_ms is None:
        loop_start_ms = 0

    messages = list(messages)
    if sysex_gap_ms is not None:
        messages = _apply_sysex_gap(messages, sysex_gap_ms, warnings)
    if messages:
        end_ms = max(end_ms, messages[-1].ms)

    if loop:
        if not 0 <= loop_start_ms <= end_ms:
            raise GseqError("loop start is outside the sequence")
        index = next((i for i, m in enumerate(messages) if m.ms >= loop_start_ms), len(messages))
        messages.insert(index, Message(loop_start_ms, control=OP_LOOP_START))
        _check_hanging_notes(messages, warnings)

    _check_bandwidth(messages, warnings)
    return Sequence(messages, end_ms, loop_start_ms if loop else None, warnings)


def _apply_sysex_gap(messages: list[Message], gap_ms: int, warnings: list[str]) -> list[Message]:
    out: list[Message] = []
    earliest = 0
    delayed = 0
    for message in messages:
        ms = message.ms
        if ms < earliest:
            delayed += 1
            ms = earliest
        out.append(Message(ms, message.data, message.control, message.params))
        if message.data[:1] == b"\xF0":
            wire_ms = -(-len(message.data) * 1000 // WIRE_BYTES_PER_SECOND)
            earliest = ms + wire_ms + gap_ms
    if delayed:
        warnings.append(f"--sysex-gap delayed {delayed} messages")
    return out


def _check_hanging_notes(messages: list[Message], warnings: list[str]) -> None:
    sounding: set[tuple[int, int]] = set()
    for message in messages:
        data = message.data
        if not data:
            continue
        kind, channel = data[0] & 0xF0, data[0] & 0x0F
        if kind == 0x90 and data[2]:
            sounding.add((channel, data[1]))
        elif kind == 0x80 or (kind == 0x90 and not data[2]):
            sounding.discard((channel, data[1]))
    if sounding:
        notes = ", ".join(f"ch{c + 1}:{n}" for c, n in sorted(sounding))
        warnings.append(f"notes still sounding at the loop point: {notes}")


def _check_bandwidth(messages: list[Message], warnings: list[str]) -> None:
    wire_free = Fraction(0)
    worst, worst_ms = Fraction(0), 0
    for message in messages:
        if not message.data:
            continue
        start = max(Fraction(message.ms), wire_free)
        late = start - message.ms
        if late > worst:
            worst, worst_ms = late, message.ms
        wire_free = start + Fraction(len(message.data) * 1000, WIRE_BYTES_PER_SECOND)
    if worst > 10:
        warnings.append(f"cable too slow: up to {float(worst):.0f} ms late (around {worst_ms} ms)")


# ---------------------------------------------------------------- encoding

def encode(sequence: Sequence) -> bytes:
    body = bytearray()
    channel_mask = 0
    loop_offset = 0
    last_ms = 0
    for message in sequence.messages:
        body += encode_vlq(message.ms - last_ms)
        last_ms = message.ms
        if message.control is not None:
            body += bytes([KIND_CONTROL, message.control]) + encode_vlq(len(message.params)) + message.params
            if message.control == OP_LOOP_START:
                loop_offset = len(body)
        elif message.data[0] == 0xF0:
            body += bytes([KIND_SYSEX]) + encode_vlq(len(message.data) - 1) + message.data[1:]
        else:
            body += message.data
            channel_mask |= 1 << (message.data[0] & 0x0F)
    body += encode_vlq(sequence.end_ms - last_ms) + bytes([KIND_CONTROL, OP_END, 0])
    if len(body) >= 1 << 24:
        raise GseqError("sequence longer than 16 MB")
    looping = sequence.loop_ms is not None
    header = struct.pack(
        "<4sBBHHH",
        MAGIC, VERSION_MAJOR, VERSION_MINOR, HEADER_SIZE,
        FLAG_LOOP if looping else 0, channel_mask)
    header += len(body).to_bytes(3, "little") + bytes([sequence.target])
    header += struct.pack("<I", sequence.end_ms)
    header += loop_offset.to_bytes(3, "little") + b"\0"
    header += struct.pack("<IHH", sequence.loop_ms or 0, sum(body) & 0xFFFF, 0)
    assert len(header) == HEADER_SIZE
    return bytes(header + body)


# ---------------------------------------------------------------- decoding

@dataclass
class Decoded:
    header: dict[str, int]
    records: list[tuple[int, str, bytes]]   # (ms, kind, payload)


def decode(data: bytes) -> Decoded:
    """Parse and check a GSEQ file the way the Next library will."""
    if len(data) < HEADER_SIZE or data[:4] != MAGIC:
        raise GseqError("not a GSEQ file")
    major, minor, header_size, flags, mask = struct.unpack("<BBHHH", data[4:12])
    if major != VERSION_MAJOR:
        raise GseqError(f"unsupported GSEQ major version {major}")
    length = int.from_bytes(data[12:15], "little")
    target = data[15]
    end_ms = struct.unpack("<I", data[16:20])[0]
    loop_offset = int.from_bytes(data[20:23], "little")
    loop_ms, checksum = struct.unpack("<IH", data[24:30])
    body = data[header_size:header_size + length]
    if len(body) != length:
        raise GseqError("data shorter than the header says")
    if sum(body) & 0xFFFF != checksum:
        raise GseqError("checksum mismatch")
    records: list[tuple[int, str, bytes]] = []
    pos, ms = 0, 0
    offsets = set()
    while True:
        offsets.add(pos)
        delta, pos = read_vlq(body, pos)
        ms += delta
        if pos >= len(body):
            raise GseqError("record without kind")
        kind = body[pos]
        pos += 1
        if 0x80 <= kind <= 0xEF:
            size = channel_data_length(kind)
            payload = body[pos - 1:pos + size]
            if len(payload) != 1 + size or any(b & 0x80 for b in payload[1:]):
                raise GseqError("bad channel message")
            pos += size
            records.append((ms, "midi", bytes(payload)))
        elif kind == KIND_SYSEX:
            size, pos = read_vlq(body, pos)
            payload = b"\xF0" + body[pos:pos + size]
            pos += size
            check_message(payload)
            records.append((ms, "midi", payload))
        elif kind == KIND_CONTROL:
            if pos >= len(body):
                raise GseqError("truncated control record")
            op = body[pos]
            size, pos = read_vlq(body, pos + 1)
            params = body[pos:pos + size]
            if len(params) != size:
                raise GseqError("truncated control record")
            pos += size
            records.append((ms, f"control:{op:02x}", bytes(params)))
            if op == OP_END:
                break
        else:
            raise GseqError(f"invalid record kind {kind:02X}")
    if pos != len(body):
        raise GseqError("bytes after the end record")
    if ms != end_ms:
        raise GseqError("end record time does not match the header")
    if flags & FLAG_LOOP and loop_offset not in offsets:
        raise GseqError("loop offset is not at a record boundary")
    header = {"major": major, "minor": minor, "flags": flags, "channel_mask": mask,
              "length": length, "target": target, "end_ms": end_ms, "loop_offset": loop_offset, "loop_ms": loop_ms}
    return Decoded(header, records)


def wire_bytes(decoded: Decoded) -> bytes:
    """Bytes that a player sends for one pass (no loop repetition)."""
    return b"".join(payload for _, kind, payload in decoded.records if kind == "midi")


# ---------------------------------------------------------------- CLI

def convert(source: bytes, is_json: bool, loop: bool = False, loop_start_ms: int | None = None,
            sysex_gap_ms: int | None = None, target: str = "any") -> tuple[bytes, Sequence]:
    warnings: list[str] = []
    if is_json:
        messages, end_ms, markers = json_to_messages(source.decode("utf-8"))
    else:
        messages, end_ms, markers = smf_to_messages(source, warnings)
    sequence = build_sequence(messages, end_ms, markers, loop, loop_start_ms, sysex_gap_ms)
    sequence.warnings[:0] = warnings
    sequence.target = TARGETS[target]
    return encode(sequence), sequence


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help=".mid/.smf or .json")
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--loop", action="store_true", help="loop the whole piece")
    parser.add_argument("--loop-start-ms", type=int, help="loop back to this time")
    parser.add_argument("--sysex-gap", type=int, metavar="MS",
                        help="silence after each SysEx leaves the cable (real MT-32)")
    parser.add_argument("--target", choices=tuple(TARGETS), default="any",
                        help="synth the music was made for (header byte 15)")
    parser.add_argument("--report", type=Path, help="write a JSON report")
    args = parser.parse_args(argv)
    try:
        output, sequence = convert(args.input.read_bytes(), args.input.suffix.lower() == ".json",
                                   args.loop, args.loop_start_ms, args.sysex_gap, args.target)
    except GseqError as error:
        print(f"{args.input}: {error}", file=sys.stderr)
        return 1
    args.output.write_bytes(output)
    decoded = decode(output)
    report = {
        "input": str(args.input), "output": str(args.output), "bytes": len(output),
        "messages": sum(1 for _, kind, _ in decoded.records if kind == "midi"),
        "wire_bytes": len(wire_bytes(decoded)), "duration_ms": decoded.header["end_ms"],
        "target": args.target, "loop_ms": sequence.loop_ms, "channel_mask": f"{decoded.header['channel_mask']:04x}",
        "banks_8k": -(-len(output) // 8192), "warnings": sequence.warnings,
    }
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{args.output}: {len(output)} bytes, {report['messages']} messages, "
          f"{report['duration_ms']} ms, {report['banks_8k']} bank(s) of 8K")
    for warning in sequence.warnings:
        print(f"warning: {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
