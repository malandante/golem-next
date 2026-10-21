import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "host"))
import fx_midi  # noqa: E402


class FxMidiTest(unittest.TestCase):
    def test_committed_files_match_generator(self):
        for name, data in fx_midi.FILES.items():
            self.assertEqual((REPO / "src" / "midi" / name).read_bytes(), data, name)

    def test_dry_zeroes_reverb_and_chorus_on_all_channels(self):
        data = fx_midi.FILES["DRY.MID"]
        for channel in range(16):
            self.assertIn(bytes([0xB0 | channel, 91, 0]), data)
            self.assertIn(bytes([0xB0 | channel, 93, 0]), data)

    def test_effects_restores_gm_defaults(self):
        data = fx_midi.FILES["EFFECTS.MID"]
        for channel in range(16):
            self.assertIn(bytes([0xB0 | channel, 91, 40]), data)
            self.assertIn(bytes([0xB0 | channel, 93, 0]), data)


if __name__ == "__main__":
    unittest.main()
