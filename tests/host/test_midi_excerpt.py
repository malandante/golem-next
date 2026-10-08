from __future__ import annotations

import sys
import unittest
from fractions import Fraction
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
BUILD = Path(__file__).resolve().parents[2] / "build"
sys.path.insert(0, str(TOOLS))

from midi_excerpt import crop_smf, encode_vlq  # noqa: E402
from midi_manifest import inspect_smf  # noqa: E402


class MidiExcerptTests(unittest.TestCase):
    def test_vlq_encoding(self) -> None:
        self.assertEqual(encode_vlq(0), b"\x00")
        self.assertEqual(encode_vlq(96), b"\x60")
        self.assertEqual(encode_vlq(768), b"\x86\x00")

    def test_crop_preserves_tracks_and_sets_duration(self) -> None:
        BUILD.mkdir(exist_ok=True)
        output = BUILD / "test-midi-excerpt-duration.mid"
        try:
            result = crop_smf(FIXTURES / "TEST1.MID", output, Fraction(1))
            manifest = inspect_smf(output)
        finally:
            output.unlink(missing_ok=True)

        self.assertEqual(result["end_tick"], 192)
        self.assertEqual(manifest["tracks"], 2)
        self.assertEqual(manifest["duration_seconds"], 1.0)

    def test_crop_keeps_early_sysex(self) -> None:
        BUILD.mkdir(exist_ok=True)
        output = BUILD / "test-midi-excerpt-sysex.mid"
        try:
            crop_smf(FIXTURES / "TESTSAB.MID", output, Fraction(5))
            manifest = inspect_smf(output)
        finally:
            output.unlink(missing_ok=True)

        self.assertEqual(manifest["sysex_events"], 1)
        self.assertEqual(manifest["duration_seconds"], 5.0)


if __name__ == "__main__":
    unittest.main()
