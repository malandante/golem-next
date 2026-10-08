from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tools" / "host"))

from summarize_physical_timing import percentile, summarize_report  # noqa: E402


class PhysicalTimingSummaryTests(unittest.TestCase):
    def test_nearest_rank_percentile(self) -> None:
        self.assertEqual(percentile([4, 1, 3, 2], 95), 4)

    def test_separates_systematic_error_from_jitter(self) -> None:
        report = {
            "capture": "h4-50-3_5.csv",
            "passed": True,
            "timing": [
                {"run": 1, "event": "C off", "error_s": 0.003},
                {"run": 2, "event": "C off", "error_s": 0.005},
                {"run": 1, "event": "D off", "error_s": -0.001},
                {"run": 2, "event": "D off", "error_s": 0.001},
            ],
        }
        summary = summarize_report(report)
        self.assertEqual(summary["runs"], 2)
        self.assertAlmostEqual(summary["worst_peak_to_peak_jitter_ms"], 2.0)
        self.assertAlmostEqual(summary["worst_abs_error_ms"], 5.0)


if __name__ == "__main__":
    unittest.main()
