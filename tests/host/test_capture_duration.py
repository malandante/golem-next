import sys
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
sys.path.insert(0, str(TOOLS))

from capture_duration import validate_capture, validate_capture_matrix  # noqa: E402


class DurationCaptureTests(unittest.TestCase):
    def test_accept_path(self):
        data = bytes([0xFE]) * 512 + bytes([0xF2, 0x00, 0x01, 0xF3, 0x03, 0xF9])
        self.assertEqual(validate_capture(data, 0, 1), (1, 3))

    def test_fifo_full_path(self):
        data = bytes([0xF2, 0x01, 0x00, 0xF3, 0x02, 0xF9])
        self.assertEqual(validate_capture(data, 1, 1), (0, 2))

    def test_rejects_extra_data(self):
        with self.assertRaises(ValueError):
            validate_capture(
                bytes([0xF2, 0x01, 0x00, 0xF3, 0x03, 0xF9, 0xF8]), 1, 1
            )

    def test_all_cpu_speeds_accept_path(self):
        data = b"".join(
            bytes([0xFE]) * 512 + bytes([0xF2, 0x00, speed, 0xF3, speed])
            for speed in range(4)
        ) + bytes([0xF9])
        self.assertEqual(
            validate_capture_matrix(data, 0, 3, (0, 1, 2, 3)),
            [(0, 0), (1, 1), (2, 2), (3, 3)],
        )

    def test_matrix_rejects_wrong_effective_speed(self):
        data = bytes([0xF2, 0x01, 0x00, 0xF3, 0x00, 0xF9])
        with self.assertRaises(ValueError):
            validate_capture_matrix(data, 1, 1, (1,))


if __name__ == "__main__":
    unittest.main()
