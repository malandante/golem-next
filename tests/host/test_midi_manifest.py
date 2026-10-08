from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
sys.path.insert(0, str(TOOLS))

from midi_manifest import inspect_smf  # noqa: E402


class MidiManifestTests(unittest.TestCase):
    def test_format_zero_duration(self) -> None:
        result = inspect_smf(FIXTURES / "TEST0.MID")

        self.assertEqual(result["smf_format"], 0)
        self.assertEqual(result["tracks"], 1)
        self.assertEqual(result["ticks_per_quarter"], 96)
        self.assertEqual(result["duration_seconds"], 5.0)
        self.assertEqual(result["channel_events"], 3)

    def test_format_one_tempo_track(self) -> None:
        result = inspect_smf(FIXTURES / "TEST1.MID")

        self.assertEqual(result["smf_format"], 1)
        self.assertEqual(result["tracks"], 2)
        self.assertEqual(result["duration_seconds"], 2.5)
        self.assertEqual(result["tempo_events"], 1)

    def test_sysex_counts(self) -> None:
        result = inspect_smf(FIXTURES / "TESTSYX.MID")

        self.assertEqual(result["sysex_events"], 2)
        self.assertEqual(result["sysex_payload_bytes"], 13)
        self.assertEqual(
            result["sysex_messages"],
            [
                {
                    "track": 0,
                    "event": 0,
                    "tick": 0,
                    "status": "F0",
                    "payload_hex": "41 10 16 12 20 00",
                    "payload_bytes": 6,
                },
                {
                    "track": 0,
                    "event": 1,
                    "tick": 0,
                    "status": "F7",
                    "payload_hex": "00 54 45 53 54 20 F7",
                    "payload_bytes": 7,
                },
            ],
        )

    def test_audible_sysex_fixture_has_valid_roland_checksums(self) -> None:
        result = inspect_smf(FIXTURES / "TESTSAB.MID")
        payloads = [
            bytes.fromhex(message["payload_hex"])
            for message in result["sysex_messages"]
        ]

        self.assertEqual(result["duration_seconds"], 8.5)
        self.assertEqual(len(payloads), 2)
        self.assertTrue(all(payload[:4] == bytes.fromhex("41 10 16 12") for payload in payloads))
        self.assertTrue(all(payload[-1] == 0xF7 for payload in payloads))
        self.assertTrue(all(sum(payload[4:-1]) & 0x7F == 0 for payload in payloads))


if __name__ == "__main__":
    unittest.main()
