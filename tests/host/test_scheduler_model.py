from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
sys.path.insert(0, str(TOOLS))

from scheduler_model import analyse  # noqa: E402


class SchedulerModelTests(unittest.TestCase):
    def test_aligned_timing_fixture_has_no_50_hz_error(self) -> None:
        result = analyse(FIXTURES / "TESTTIM.MID", 50)

        self.assertEqual(result["channel_events"], 7)
        self.assertEqual(result["event_error_ms"], {"minimum": 0.0, "maximum": 0.0})

    def test_audible_fixture_reports_all_channel_events(self) -> None:
        result = analyse(FIXTURES / "TESTSAB.MID", 60)

        self.assertEqual(result["channel_events"], 5)
        self.assertEqual(result["note_on_events"], 2)

    def test_millisecond_scheduler_bounds_error_to_one_millisecond(self) -> None:
        result = analyse(FIXTURES / "TESTSAB.MID", 50, "millisecond")

        self.assertGreaterEqual(result["event_error_ms"]["minimum"], -1.0)
        self.assertEqual(result["event_error_ms"]["maximum"], 0.0)


if __name__ == "__main__":
    unittest.main()
