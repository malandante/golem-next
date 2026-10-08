from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
sys.path.insert(0, str(TOOLS))

from make_metronome import build  # noqa: E402
from midi_manifest import inspect_smf  # noqa: E402


class MakeMetronomeTests(unittest.TestCase):
    def test_default_matches_fixture(self) -> None:
        self.assertEqual(build(120, 180, 56, 37), (FIXTURES / "METRO120.MID").read_bytes())

    def test_padded_matches_fixture_and_passes_64k(self) -> None:
        data = build(120, 180, 56, 37, pad_kb=150)
        self.assertEqual(data, (FIXTURES / "METROBIG.MID").read_bytes())
        self.assertGreater(len(data), 65536)

    def test_padded_keeps_the_same_click_track(self) -> None:
        plain = build(120, 180, 56, 37)
        padded = build(120, 180, 56, 37, pad_kb=150)
        click_track = plain[14:]  # MThd chunk is 14 bytes
        self.assertTrue(padded.endswith(click_track))
        self.assertEqual(padded[8:12], b"\x00\x01\x00\x02")  # format 1, 2 tracks

    def test_padded_fixture_is_a_valid_smf(self) -> None:
        manifest = inspect_smf(FIXTURES / "METROBIG.MID")
        self.assertEqual(manifest["smf_format"], 1)
        self.assertEqual(manifest["tracks"], 2)
        self.assertAlmostEqual(manifest["duration_seconds"], 180, delta=1)


if __name__ == "__main__":
    unittest.main()
