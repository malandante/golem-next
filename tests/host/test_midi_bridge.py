from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tools" / "host"))

from midi_bridge import MidiParser, data_length, send_panic  # noqa: E402


class FakeOutput:
    def __init__(self) -> None:
        self.short_messages: list[bytes] = []
        self.sysex_messages: list[bytes] = []

    def short(self, message: bytes) -> None:
        self.short_messages.append(message)

    def sysex(self, message: bytes) -> None:
        self.sysex_messages.append(message)


class MidiParserTests(unittest.TestCase):
    def test_lengths(self) -> None:
        self.assertEqual(data_length(0x91), 2)
        self.assertEqual(data_length(0xC1), 1)
        self.assertEqual(data_length(0xF2), 2)
        self.assertEqual(data_length(0xF6), 0)

    def test_running_status_realtime_and_sysex(self) -> None:
        output = FakeOutput()
        parser = MidiParser(output)  # type: ignore[arg-type]
        stream = bytes.fromhex("91 3c 64 3d 6e f8 f0 41 f8 10 f7 f2 01 02")
        for value in stream:
            parser.feed(value)

        self.assertEqual(
            output.short_messages,
            [
                bytes.fromhex("91 3c 64"),
                bytes.fromhex("91 3d 6e"),
                bytes.fromhex("f8"),
                bytes.fromhex("f8"),
                bytes.fromhex("f2 01 02"),
            ],
        )
        self.assertEqual(output.sysex_messages, [bytes.fromhex("f0 41 10 f7")])
        self.assertEqual(parser.short_messages, 5)
        self.assertEqual(parser.sysex_passed, 1)
        self.assertEqual(parser.sysex_dropped, 0)

    def test_sysex_can_be_dropped_without_dropping_notes(self) -> None:
        output = FakeOutput()
        parser = MidiParser(output, sysex_mode="drop")  # type: ignore[arg-type]
        stream = bytes.fromhex("f0 41 10 f7 91 3c 64")
        for value in stream:
            parser.feed(value)

        self.assertEqual(output.sysex_messages, [])
        self.assertEqual(output.short_messages, [bytes.fromhex("91 3c 64")])
        self.assertEqual(parser.summary(), "short=1 sysex_passed=0 sysex_dropped=1")

    def test_detects_ordered_all_notes_off_cleanup(self) -> None:
        output = FakeOutput()
        parser = MidiParser(output, verbose=False)  # type: ignore[arg-type]

        for channel in range(16):
            for value in bytes([0xB0 + channel, 0x7B, 0x00]):
                parser.feed(value)

        self.assertTrue(parser.cleanup_complete)
        self.assertEqual(parser.cleanup_next_channel, 16)

    def test_start_cleanup_of_play_does_not_end_the_bridge(self) -> None:
        # .GOLEM play sends CC64/CC123/CC120/CC7=100 per channel before the song;
        # only the end cleanup (no CC7) may complete the bridge.
        output = FakeOutput()
        parser = MidiParser(output, verbose=False)  # type: ignore[arg-type]
        for channel in range(16):
            for value in bytes([0xB0 + channel, 0x40, 0x00, 0xB0 + channel, 0x7B, 0x00,
                                0xB0 + channel, 0x78, 0x00, 0xB0 + channel, 0x07, 0x64]):
                parser.feed(value)
        self.assertFalse(parser.cleanup_complete)

    def test_detects_full_cleanup_with_sustain_and_sound_off(self) -> None:
        output = FakeOutput()
        parser = MidiParser(output, verbose=False)  # type: ignore[arg-type]

        for channel in range(16):
            for value in bytes(
                [0xB0 + channel, 0x40, 0x00, 0xB0 + channel, 0x7B, 0x00, 0xB0 + channel, 0x78, 0x00]
            ):
                parser.feed(value)

        self.assertTrue(parser.cleanup_complete)

    def test_sound_off_for_wrong_channel_restarts_detection(self) -> None:
        output = FakeOutput()
        parser = MidiParser(output, verbose=False)  # type: ignore[arg-type]
        for value in bytes.fromhex("B0 7B 00 B5 78 00"):
            parser.feed(value)

        self.assertEqual(parser.cleanup_next_channel, 0)

    def test_unrelated_message_restarts_cleanup_detection(self) -> None:
        output = FakeOutput()
        parser = MidiParser(output, verbose=False)  # type: ignore[arg-type]
        stream = bytes.fromhex("B0 7B 00 B1 7B 00 91 3C 64")
        stream += b"".join(bytes([0xB0 + channel, 0x7B, 0x00]) for channel in range(16))
        for value in stream:
            parser.feed(value)

        self.assertTrue(parser.cleanup_complete)

    def test_panic_silences_every_channel(self) -> None:
        output = FakeOutput()

        send_panic(output)  # type: ignore[arg-type]

        self.assertEqual(len(output.short_messages), 48)
        for channel in range(16):
            start = channel * 3
            status = 0xB0 + channel
            self.assertEqual(
                output.short_messages[start : start + 3],
                [
                    bytes([status, 0x40, 0x00]),
                    bytes([status, 0x7B, 0x00]),
                    bytes([status, 0x78, 0x00]),
                ],
            )


if __name__ == "__main__":
    unittest.main()
