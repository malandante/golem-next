from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tools" / "host"))

from capture_timing import (  # noqa: E402
    MARKERS,
    NOTE_MARKERS,
    find_markers,
    measure_note_durations,
)


class TimingMarkerTests(unittest.TestCase):
    def test_finds_markers_in_order(self) -> None:
        data = b"\xc1\x08" + b"".join(marker.message for marker in MARKERS)
        timestamps = [index / 1000 for index in range(len(data))]

        found = find_markers(data, timestamps)

        self.assertEqual([marker for marker, _ in found], list(MARKERS))
        self.assertEqual(found[0][1], timestamps[2])

    def test_rejects_missing_marker(self) -> None:
        with self.assertRaisesRegex(ValueError, "missing MIDI marker"):
            find_markers(MARKERS[0].message, [0.0] * len(MARKERS[0].message))

    def test_finds_note_markers(self) -> None:
        data = b"".join(marker.message for marker in NOTE_MARKERS)
        timestamps = [index / 1000 for index in range(len(data))]

        found = find_markers(data, timestamps, NOTE_MARKERS)

        self.assertEqual([marker for marker, _ in found], list(NOTE_MARKERS))

    def test_measures_each_note_independently(self) -> None:
        found = [
            (NOTE_MARKERS[0], 10.0),
            (NOTE_MARKERS[1], 11.0),
            (NOTE_MARKERS[2], 12.5),
            (NOTE_MARKERS[3], 13.5),
        ]

        rows = measure_note_durations(found)

        self.assertEqual(rows[0], ("low duration", 1.0, 1.0, 0.0))
        self.assertEqual(rows[1], ("high duration", 1.0, 1.0, 0.0))


if __name__ == "__main__":
    unittest.main()
