from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tools" / "host"))

from golem_protocol import (  # noqa: E402
    ACCEPTED,
    ERROR,
    READY,
    SET_ROM_SET,
    SET_SOUNDFONT,
    SET_SYNTH,
    GolemResponse,
    ResponseStream,
    Transaction,
    TransactionState,
    decode,
    get_status,
    response,
    select_fluidsynth,
    select_mt32,
    select_rom_set,
    select_soundfont,
)


class GolemProtocolTests(unittest.TestCase):
    def test_request_vectors_match_mt32_pi(self) -> None:
        self.assertEqual(get_status(0x12), bytes.fromhex("f0 7d 47 4c 4d 01 12 00 f7"))
        self.assertEqual(select_mt32(0x12), bytes.fromhex("f0 7d 47 4c 4d 01 12 01 00 f7"))
        self.assertEqual(select_fluidsynth(0x12), bytes.fromhex("f0 7d 47 4c 4d 01 12 01 01 f7"))
        self.assertEqual(select_rom_set(0x12, 2), bytes.fromhex("f0 7d 47 4c 4d 01 12 02 02 f7"))
        self.assertEqual(select_soundfont(0x12, 511), bytes.fromhex("f0 7d 47 4c 4d 01 12 03 7f 03 f7"))

    def test_range_validation(self) -> None:
        select_soundfont(0x7F, 0x3FFF)
        with self.assertRaises(ValueError):
            select_soundfont(1, 0x4000)
        with self.assertRaises(ValueError):
            select_rom_set(1, 3)

    def test_decode_response(self) -> None:
        self.assertEqual(
            decode(bytes.fromhex("f0 7d 47 4c 4d 01 12 41 01 01 f7")),
            GolemResponse(0x12, READY, SET_SYNTH, b"\x01"),
        )
        self.assertIsNone(decode(bytes.fromhex("f0 7d 47 4c 4d 02 12 41 01 01 f7")))
        self.assertIsNone(decode(bytes.fromhex("f0 7d 47 4c 4d 01 12 41 03 01 f7")))

    def test_response_vector_matches_mt32_pi(self) -> None:
        self.assertEqual(
            response(0x12, READY, SET_SYNTH, b"\x01"),
            bytes.fromhex("f0 7d 47 4c 4d 01 12 41 01 01 f7"),
        )

    def test_stream_handles_noise_fragmentation_and_restart(self) -> None:
        stream = ResponseStream()
        self.assertEqual(stream.feed(bytes.fromhex("90 3c f0 7d 47")), [])
        responses = stream.feed(bytes.fromhex("f0 7d 47 4c 4d 01 12 40 01 f7"))
        self.assertEqual(responses, [GolemResponse(0x12, ACCEPTED, SET_SYNTH, b"")])

    def test_transaction_requires_accepted_then_ready(self) -> None:
        transaction = Transaction(0x12, SET_SYNTH)
        self.assertFalse(transaction.consume(GolemResponse(0x12, READY, SET_SYNTH, b"\x01")))
        self.assertTrue(transaction.consume(GolemResponse(0x12, ACCEPTED, SET_SYNTH, b"")))
        self.assertEqual(transaction.state, TransactionState.WAITING_COMPLETION)
        self.assertTrue(transaction.consume(GolemResponse(0x12, READY, SET_SYNTH, b"\x01")))
        self.assertEqual(transaction.state, TransactionState.READY)
        self.assertFalse(transaction.consume(GolemResponse(0x12, ERROR, SET_SYNTH, b"\x06")))
        self.assertEqual(transaction.state, TransactionState.READY)

    def test_transaction_ignores_stale_response(self) -> None:
        transaction = Transaction(0x12, SET_ROM_SET)
        self.assertFalse(transaction.consume(GolemResponse(0x11, ACCEPTED, SET_ROM_SET, b"")))
        self.assertEqual(transaction.state, TransactionState.WAITING_ACCEPTED)

    def test_error_before_or_after_accepted_is_terminal(self) -> None:
        for accept_first in (False, True):
            transaction = Transaction(0x12, SET_SOUNDFONT)
            if accept_first:
                transaction.consume(GolemResponse(0x12, ACCEPTED, SET_SOUNDFONT, b""))
            self.assertTrue(transaction.consume(GolemResponse(0x12, ERROR, SET_SOUNDFONT, b"\x05")))
            self.assertEqual(transaction.state, TransactionState.ERROR)
            self.assertEqual(transaction.payload, b"\x05")

    def test_timeout_is_explicit_terminal_state(self) -> None:
        transaction = Transaction(0x12, SET_SYNTH)
        transaction.timeout()
        self.assertEqual(transaction.state, TransactionState.TIMED_OUT)


if __name__ == "__main__":
    unittest.main()
