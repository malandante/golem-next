from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
sys.path.insert(0, str(TOOLS))

import gseq  # noqa: E402
from gseq import GseqError, convert, decode, wire_bytes  # noqa: E402


def vlq(value: int) -> bytes:
    return gseq.encode_vlq(value)


def smf(tracks: list[bytes], division: int = 96, fmt: int | None = None) -> bytes:
    fmt = (0 if len(tracks) == 1 else 1) if fmt is None else fmt
    out = b"MThd" + struct.pack(">IHHH", 6, fmt, len(tracks), division)
    for track in tracks:
        out += b"MTrk" + struct.pack(">I", len(track)) + track
    return out


END = vlq(0) + b"\xFF\x2F\x00"


def tempo(us: int) -> bytes:
    return b"\xFF\x51\x03" + us.to_bytes(3, "big")


def marker(text: str) -> bytes:
    body = text.encode()
    return b"\xFF\x06" + vlq(len(body)) + body


def midi_records(data: bytes) -> list[tuple[int, bytes]]:
    return [(ms, payload) for ms, kind, payload in decode(data).records if kind == "midi"]


class HeaderTests(unittest.TestCase):
    def test_header_fields_and_checksum(self) -> None:
        track = vlq(0) + b"\x91\x3c\x64" + vlq(96) + b"\x81\x3c\x00" + END
        out, _ = convert(smf([track]), False)
        self.assertEqual(out[:4], b"GSEQ")
        major, minor, size, flags, mask = struct.unpack("<BBHHH", out[4:12])
        self.assertEqual((major, minor, size, flags), (1, 0, 32, 0))
        self.assertEqual(mask, 0x0002)  # channel 2
        decoded = decode(out)
        self.assertEqual(decoded.header["end_ms"], 500)
        self.assertEqual(decoded.header["length"], len(out) - 32)

    def test_target_profile_in_header(self) -> None:
        track = vlq(0) + b"\x90\x3c\x64" + END
        self.assertEqual(decode(convert(smf([track]), False)[0]).header["target"], 0)
        out, _ = convert(smf([track]), False, target="mt32")
        self.assertEqual(out[15], 1)
        self.assertEqual(decode(convert(smf([track]), False, target="gm")[0]).header["target"], 2)

    def test_corrupted_byte_is_detected(self) -> None:
        out, _ = convert(smf([vlq(0) + b"\x90\x3c\x64" + END]), False)
        broken = bytearray(out)
        broken[-4] ^= 0x01
        with self.assertRaises(GseqError):
            decode(bytes(broken))

    def test_unknown_major_version_is_rejected(self) -> None:
        out = bytearray(convert(smf([vlq(0) + b"\x90\x3c\x64" + END]), False)[0])
        out[4] = 2
        with self.assertRaises(GseqError):
            decode(bytes(out))


class TimingTests(unittest.TestCase):
    def test_default_tempo_and_tempo_change(self) -> None:
        # 96 PPQN, 120 BPM: 96 ticks = 500 ms; then 60 BPM: 96 ticks = 1000 ms.
        track = (vlq(0) + b"\x90\x3c\x64" + vlq(96) + tempo(1_000_000)
                 + vlq(0) + b"\x80\x3c\x00" + vlq(96) + b"\x90\x3e\x64" + END)
        records = midi_records(convert(smf([track]), False)[0])
        self.assertEqual([ms for ms, _ in records], [0, 500, 1500])

    def test_rounding_does_not_accumulate(self) -> None:
        # 1 tick = 5000/3 us = 1.666.. ms (PPQN 300 at 120 BPM): 300 notes, one per tick.
        track = b"".join(vlq(1) + b"\x90\x3c\x01" for _ in range(300)) + END
        records = midi_records(convert(smf([track], division=300), False)[0])
        self.assertEqual(records[-1][0], 500)
        self.assertEqual([ms for ms, _ in records[:4]], [2, 3, 5, 7])

    def test_merge_order_and_explicit_status(self) -> None:
        track0 = vlq(0) + tempo(500_000) + vlq(0) + b"\x92\x40\x40" + END
        # running status in track 1 must come out with explicit status
        track1 = vlq(0) + b"\x91\x3c\x64" + vlq(0) + b"\x3e\x64" + END
        records = midi_records(convert(smf([track0, track1]), False)[0])
        self.assertEqual([p for _, p in records],
                         [b"\x92\x40\x40", b"\x91\x3c\x64", b"\x91\x3e\x64"])

    def test_same_bytes_as_mt32_play_for_test1(self) -> None:
        records = midi_records(convert((FIXTURES / "TEST1.MID").read_bytes(), False)[0])
        self.assertEqual(b"".join(p for _, p in records), bytes.fromhex("c1 00 91 40 64 91 40 00"))


class SysexTests(unittest.TestCase):
    def test_sysex_kept_whole(self) -> None:
        records = midi_records(convert((FIXTURES / "TESTSYX.MID").read_bytes(), False)[0])
        self.assertEqual(records[0][1], bytes.fromhex("f0 41 10 16 12 20 00 00 54 45 53 54 20 f7"))

    def test_split_sysex_is_joined_with_a_warning(self) -> None:
        _, sequence = convert((FIXTURES / "TESTSPL.MID").read_bytes(), False)
        payloads = [m.data for m in sequence.messages if m.data]
        self.assertEqual(payloads[0], bytes.fromhex("f0 41 10 16 12 20 00 00 54 45 53 54 20 f7"))
        self.assertTrue(any("joined" in w for w in sequence.warnings))

    def test_invalid_sysex_is_rejected(self) -> None:
        with self.assertRaises(GseqError):
            convert((FIXTURES / "BADSYX7.MID").read_bytes(), False)

    def test_sysex_gap_delays_only_colliding_messages(self) -> None:
        sysex = b"\xF0" + vlq(10) + bytes(9) + b"\xF7"   # 11 bytes on the cable: 4 ms
        track = (vlq(0) + sysex + vlq(0) + b"\x90\x3c\x64"
                 + vlq(96) + b"\x80\x3c\x00" + END)
        out, sequence = convert(smf([track]), False, sysex_gap_ms=20)
        self.assertEqual([ms for ms, _ in midi_records(out)], [0, 24, 500])
        self.assertTrue(any("delayed 1" in w for w in sequence.warnings))


class LoopTests(unittest.TestCase):
    def test_loop_markers(self) -> None:
        track = (vlq(0) + b"\x90\x3c\x64" + vlq(48) + marker("loopStart")
                 + vlq(0) + b"\x80\x3c\x00" + vlq(0) + b"\x90\x3e\x64"
                 + vlq(48) + b"\x80\x3e\x00" + vlq(0) + marker("loopEnd")
                 + vlq(48) + b"\x90\x40\x64" + END)
        out, sequence = convert(smf([track]), False)
        decoded = decode(out)
        self.assertEqual(decoded.header["flags"], 1)
        self.assertEqual(decoded.header["loop_ms"], 250)
        self.assertEqual(decoded.header["end_ms"], 500)
        self.assertTrue(any("dropped" in w for w in sequence.warnings))
        # the loop offset points just after the loop-start control record
        body = out[32:]
        ms, _ = gseq.read_vlq(body, decoded.header["loop_offset"])
        self.assertEqual(body[decoded.header["loop_offset"] + 1], 0x80)

    def test_hanging_note_at_loop_point_is_reported(self) -> None:
        track = vlq(0) + b"\x90\x3c\x64" + END
        _, sequence = convert(smf([track]), False, loop=True)
        self.assertTrue(any("ch1:60" in w for w in sequence.warnings))


class InputTests(unittest.TestCase):
    def test_json_input_and_notice(self) -> None:
        doc = {"messages": [{"ms": 0, "bytes": "c1 05"}, {"ms": 10, "notice": 7},
                            {"ms": 40, "bytes": "91 3c 64"}], "end_ms": 100}
        out, _ = convert(json.dumps(doc).encode(), True)
        decoded = decode(out)
        kinds = [(ms, kind) for ms, kind, _ in decoded.records]
        self.assertEqual(kinds, [(0, "midi"), (10, "control:01"), (40, "midi"), (100, "control:00")])

    def test_rejected_inputs(self) -> None:
        for name in ("BADFMT2.MID", "BADSMPTE.MID", "BADTRNC.MID", "BADVLQ.MID"):
            with self.subTest(name=name), self.assertRaises(GseqError):
                convert((FIXTURES / name).read_bytes(), False)

    def test_bandwidth_warning(self) -> None:
        notes = b"".join(vlq(0) + bytes([0x90, n, 0x64]) for n in range(40, 90))
        _, sequence = convert(smf([notes + END]), False)
        self.assertTrue(any("cable too slow" in w for w in sequence.warnings))

    def test_cli_writes_file_and_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out, report = Path(tmp) / "t.gsq", Path(tmp) / "t.json"
            code = gseq.main([str(FIXTURES / "METRO120.MID"), "-o", str(out),
                              "--loop", "--report", str(report)])
            self.assertEqual(code, 0)
            data = json.loads(report.read_text())
            self.assertEqual(data["messages"], 1 + 2 * 360)  # program change + 360 on/off pairs
            self.assertEqual(decode(out.read_bytes()).header["flags"], 1)


if __name__ == "__main__":
    unittest.main()
