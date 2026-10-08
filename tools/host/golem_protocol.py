#!/usr/bin/env python3
"""Golem v1 request/response codec and transaction state machine."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto

MANUFACTURER_ID = 0x7D
SIGNATURE = bytes((0x47, 0x4C, 0x4D))
PROTOCOL_VERSION = 0x01

GET_STATUS = 0x00
SET_SYNTH = 0x01
SET_ROM_SET = 0x02
SET_SOUNDFONT = 0x03

ACCEPTED = 0x40
READY = 0x41
ERROR = 0x42
STATUS = 0x43

SYNTH_MT32 = 0x00
SYNTH_SOUNDFONT = 0x01
MAX_SOUNDFONT_INDEX = 0x3FFF


@dataclass(frozen=True)
class GolemResponse:
    transaction: int
    response: int
    command: int
    payload: bytes


class TransactionState(Enum):
    WAITING_ACCEPTED = auto()
    WAITING_COMPLETION = auto()
    READY = auto()
    ERROR = auto()
    TIMED_OUT = auto()


def _seven_bit(value: int, name: str) -> int:
    if not 0 <= value <= 0x7F:
        raise ValueError(f"{name} must be in range 0..127")
    return value


def request(transaction: int, command: int, payload: bytes = b"") -> bytes:
    _seven_bit(transaction, "transaction")
    _seven_bit(command, "command")
    if any(value & 0x80 for value in payload):
        raise ValueError("SysEx payload bytes must be seven-bit")
    return bytes((0xF0, MANUFACTURER_ID)) + SIGNATURE + bytes(
        (PROTOCOL_VERSION, transaction, command)
    ) + payload + bytes((0xF7,))


def response(
    transaction: int, response_type: int, command: int, payload: bytes = b""
) -> bytes:
    _seven_bit(transaction, "transaction")
    _seven_bit(response_type, "response")
    _seven_bit(command, "command")
    if any(value & 0x80 for value in payload):
        raise ValueError("SysEx payload bytes must be seven-bit")
    return bytes((0xF0, MANUFACTURER_ID)) + SIGNATURE + bytes(
        (PROTOCOL_VERSION, transaction, response_type, command)
    ) + payload + bytes((0xF7,))


def get_status(transaction: int) -> bytes:
    return request(transaction, GET_STATUS)


def select_mt32(transaction: int) -> bytes:
    return request(transaction, SET_SYNTH, bytes((SYNTH_MT32,)))


def select_fluidsynth(transaction: int) -> bytes:
    return request(transaction, SET_SYNTH, bytes((SYNTH_SOUNDFONT,)))


def select_rom_set(transaction: int, index: int) -> bytes:
    if index not in (0, 1, 2):
        raise ValueError("ROM set must be 0 (old), 1 (new), or 2 (CM-32L)")
    return request(transaction, SET_ROM_SET, bytes((index,)))


def select_soundfont(transaction: int, index: int) -> bytes:
    if not 0 <= index <= MAX_SOUNDFONT_INDEX:
        raise ValueError("SoundFont index must be in range 0..16383")
    return request(transaction, SET_SOUNDFONT, bytes((index & 0x7F, index >> 7)))


def decode(message: bytes) -> GolemResponse | None:
    if len(message) < 10 or message[0] != 0xF0 or message[-1] != 0xF7:
        return None
    if message[1] != MANUFACTURER_ID or message[2:5] != SIGNATURE:
        return None
    if message[5] != PROTOCOL_VERSION or any(value & 0x80 for value in message[1:-1]):
        return None
    response = message[7]
    payload = message[9:-1]
    if response == ACCEPTED and payload:
        return None
    if response == ERROR and len(payload) != 1:
        return None
    if response not in (ACCEPTED, READY, ERROR, STATUS):
        return None
    if response == READY:
        expected = 2 if message[8] == SET_SOUNDFONT else 1
        if (
            message[8] not in (SET_SYNTH, SET_ROM_SET, SET_SOUNDFONT)
            or len(payload) != expected
        ):
            return None
    if response == STATUS and (message[8] != GET_STATUS or len(payload) != 7):
        return None
    return GolemResponse(message[6], response, message[8], payload)


class ResponseStream:
    """Extract complete Golem responses from arbitrary UART byte chunks."""

    def __init__(self, max_frame: int = 32) -> None:
        self._frame = bytearray()
        self._max_frame = max_frame

    def feed(self, chunk: bytes) -> list[GolemResponse]:
        responses: list[GolemResponse] = []
        for value in chunk:
            if value == 0xF0:
                self._frame = bytearray((value,))
                continue
            if not self._frame:
                continue
            if value & 0x80 and value != 0xF7:
                self._frame.clear()
                continue
            self._frame.append(value)
            if len(self._frame) > self._max_frame:
                self._frame.clear()
                continue
            if value == 0xF7:
                decoded = decode(bytes(self._frame))
                self._frame.clear()
                if decoded is not None:
                    responses.append(decoded)
        return responses


class Transaction:
    """Match one request and reject stale or out-of-order completions."""

    def __init__(self, transaction: int, command: int) -> None:
        self.transaction = _seven_bit(transaction, "transaction")
        self.command = _seven_bit(command, "command")
        self.state = TransactionState.WAITING_ACCEPTED
        self.payload = b""

    def consume(self, response: GolemResponse) -> bool:
        if (response.transaction, response.command) != (self.transaction, self.command):
            return False
        if self.state in (
            TransactionState.READY,
            TransactionState.ERROR,
            TransactionState.TIMED_OUT,
        ):
            return False
        if response.response == ERROR:
            self.payload = response.payload
            self.state = TransactionState.ERROR
            return True
        if self.state is TransactionState.WAITING_ACCEPTED and response.response == ACCEPTED:
            self.state = TransactionState.WAITING_COMPLETION
            return True
        expected = STATUS if self.command == GET_STATUS else READY
        if self.state is TransactionState.WAITING_COMPLETION and response.response == expected:
            self.payload = response.payload
            self.state = TransactionState.READY
            return True
        return False

    def timeout(self) -> None:
        if self.state not in (TransactionState.READY, TransactionState.ERROR):
            self.state = TransactionState.TIMED_OUT
