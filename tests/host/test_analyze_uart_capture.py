from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tools" / "host"))

from analyze_uart_capture import ORACLES, compare_exact, read_capture, timing_runs  # noqa: E402


class PhysicalCaptureTests(unittest.TestCase):
    def write_csv(self, body: str) -> Path:
        temporary = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
        self.addCleanup(Path(temporary.name).unlink, missing_ok=True)
        with temporary:
            temporary.write(body)
        return Path(temporary.name)

    def test_reads_logic_style_hex_and_filters_direction(self) -> None:
        path = self.write_csv(
            "Time [s],Value,Direction,Parity Error\n"
            "0.000,0x91,TX,false\n"
            "0.001,0x7D,RX,false\n"
            "0.002,0x3C,TX,false\n"
            "0.003,0x64,TX,false\n"
        )
        capture = read_capture(path, direction="TX")
        self.assertEqual(capture.data, bytes.fromhex("91 3c 64"))
        self.assertEqual(capture.timestamps, [0.0, 0.002, 0.003])

    def test_scales_microseconds_and_checks_timing(self) -> None:
        path = self.write_csv(
            "Time [us],Data\n"
            "0,0x90\n0,0x00\n0,0x01\n"
            "1000000,0x80\n1000000,0x00\n1000000,0x00\n"
            "1000000,0x9f\n1000000,0x7f\n1000000,0x7f\n"
            "2000000,0x8f\n2000000,0x7f\n2000000,0x00\n"
        )
        rows = timing_runs(read_capture(path), "note", 1)[0]
        self.assertEqual([row[2] for row in rows], [1.0, 1.0])

    def test_finds_repeated_timing_runs_in_one_capture(self) -> None:
        sequence = (
            "0,0x90\n0,0x00\n0,0x01\n"
            "1000000,0x80\n1000000,0x00\n1000000,0x00\n"
            "1000000,0x9f\n1000000,0x7f\n1000000,0x7f\n"
            "2000000,0x8f\n2000000,0x7f\n2000000,0x00\n"
        )
        second = (
            "3000000,0x90\n3000000,0x00\n3000000,0x01\n"
            "4000000,0x80\n4000000,0x00\n4000000,0x00\n"
            "4000000,0x9f\n4000000,0x7f\n4000000,0x7f\n"
            "5000000,0x8f\n5000000,0x7f\n5000000,0x00\n"
        )
        path = self.write_csv("Time [us],Data\n" + sequence + second)
        runs = timing_runs(read_capture(path), "note", 2)
        self.assertEqual(len(runs), 2)
        self.assertEqual([row[2] for row in runs[1]], [1.0, 1.0])

    def test_rejects_decoder_errors(self) -> None:
        path = self.write_csv("Time [s],Value,Framing Error\n0,0x91,true\n")
        with self.assertRaisesRegex(ValueError, "decoder error"):
            read_capture(path)

    def test_reports_first_exact_mismatch(self) -> None:
        passed, detail = compare_exact(bytes.fromhex("91 3d"), bytes.fromhex("91 3c"))
        self.assertFalse(passed)
        self.assertIn("byte 1", detail)

    def test_any_byte_matches_the_golem_transaction(self) -> None:
        expected = bytes.fromhex("f0 7d 47 4c 4d 01 ff 00 f7")
        self.assertTrue(compare_exact(bytes.fromhex("f0 7d 47 4c 4d 01 3a 00 f7"), expected)[0])
        self.assertFalse(compare_exact(bytes.fromhex("f0 7d 47 4c 4d 01 3a 01 f7"), expected)[0])

    def test_return_oracle_is_test1_followed_by_basic_marker(self) -> None:
        self.assertEqual(ORACLES["test1-return"][:-1], ORACLES["test1"])
        self.assertEqual(ORACLES["test1-return"][-1:], b"\xf9")

    def test_memory_oracle_is_status_note_then_test1_then_marker(self) -> None:
        self.assertEqual(ORACLES["memory"][:9], bytes.fromhex("f0 7d 47 4c 4d 01 ff 00 f7"))
        self.assertEqual(ORACLES["memory"][9:15], bytes.fromhex("90 3c 64 80 3c 00"))
        self.assertTrue(ORACLES["memory"].endswith(ORACLES["test1-return"]))

    def test_test1_oracle_includes_ordered_cleanup(self) -> None:
        self.assertEqual(ORACLES["test1"][:12], bytes.fromhex("b0 40 00 b0 7b 00 b0 78 00 b0 07 64"))
        self.assertEqual(ORACLES["test1"][192:200], bytes.fromhex("c1 00 91 40 64 91 40 00"))
        self.assertEqual(ORACLES["test1"][200:209], bytes.fromhex("b0 40 00 b0 7b 00 b0 78 00"))
        self.assertEqual(ORACLES["test1"][-9:], bytes.fromhex("bf 40 00 bf 7b 00 bf 78 00"))
        self.assertEqual(len(ORACLES["test1"]), 16 * 12 + 8 + 16 * 9)


if __name__ == "__main__":
    unittest.main()
