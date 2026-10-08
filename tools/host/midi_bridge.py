#!/usr/bin/env python3
"""Forward the CSpect golem-next UART TCP stream to a Windows MIDI device."""

from __future__ import annotations

import argparse
import ctypes
import socket
import sys
import time
from ctypes import wintypes

MMSYSERR_NOERROR = 0
MHDR_DONE = 0x00000001


class MIDIOUTCAPSW(ctypes.Structure):
    _fields_ = [
        ("wMid", wintypes.WORD),
        ("wPid", wintypes.WORD),
        ("vDriverVersion", wintypes.DWORD),
        ("szPname", wintypes.WCHAR * 32),
        ("wTechnology", wintypes.WORD),
        ("wVoices", wintypes.WORD),
        ("wNotes", wintypes.WORD),
        ("wChannelMask", wintypes.WORD),
        ("dwSupport", wintypes.DWORD),
    ]


class MIDIHDR(ctypes.Structure):
    pass


MIDIHDR._fields_ = [
    ("lpData", ctypes.c_void_p),
    ("dwBufferLength", wintypes.DWORD),
    ("dwBytesRecorded", wintypes.DWORD),
    ("dwUser", ctypes.c_size_t),
    ("dwFlags", wintypes.DWORD),
    ("lpNext", ctypes.POINTER(MIDIHDR)),
    ("reserved", ctypes.c_size_t),
    ("dwOffset", wintypes.DWORD),
    ("dwReserved", ctypes.c_size_t * 8),
]


class WinMidiOut:
    def __init__(self, device_id: int):
        self.api = ctypes.windll.winmm
        self.handle = ctypes.c_void_p()
        result = self.api.midiOutOpen(ctypes.byref(self.handle), device_id, 0, 0, 0)
        if result != MMSYSERR_NOERROR:
            raise OSError(f"midiOutOpen failed with code {result}")

    @staticmethod
    def devices() -> list[tuple[int, str]]:
        api = ctypes.windll.winmm
        result = []
        for device_id in range(api.midiOutGetNumDevs()):
            caps = MIDIOUTCAPSW()
            status = api.midiOutGetDevCapsW(
                device_id, ctypes.byref(caps), ctypes.sizeof(caps)
            )
            if status == MMSYSERR_NOERROR:
                result.append((device_id, caps.szPname))
        return result

    def short(self, message: bytes) -> None:
        packed = sum(value << (8 * index) for index, value in enumerate(message))
        result = self.api.midiOutShortMsg(self.handle, packed)
        if result != MMSYSERR_NOERROR:
            raise OSError(f"midiOutShortMsg failed with code {result}")

    def sysex(self, message: bytes) -> None:
        data = ctypes.create_string_buffer(message)
        header = MIDIHDR()
        header.lpData = ctypes.cast(data, ctypes.c_void_p)
        header.dwBufferLength = len(message)
        header.dwBytesRecorded = len(message)
        size = ctypes.sizeof(header)
        result = self.api.midiOutPrepareHeader(self.handle, ctypes.byref(header), size)
        if result != MMSYSERR_NOERROR:
            raise OSError(f"midiOutPrepareHeader failed with code {result}")
        try:
            result = self.api.midiOutLongMsg(self.handle, ctypes.byref(header), size)
            if result != MMSYSERR_NOERROR:
                raise OSError(f"midiOutLongMsg failed with code {result}")
            while not header.dwFlags & MHDR_DONE:
                time.sleep(0.001)
        finally:
            self.api.midiOutUnprepareHeader(self.handle, ctypes.byref(header), size)

    def close(self) -> None:
        if self.handle:
            self.api.midiOutReset(self.handle)
            self.api.midiOutClose(self.handle)
            self.handle = ctypes.c_void_p()

    def __enter__(self) -> "WinMidiOut":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def send_panic(output: WinMidiOut) -> None:
    """Release sustained and sounding notes on every MIDI channel."""
    for channel in range(16):
        status = 0xB0 + channel
        output.short(bytes([status, 0x40, 0x00]))  # Sustain pedal off
        output.short(bytes([status, 0x7B, 0x00]))  # All Notes Off
        output.short(bytes([status, 0x78, 0x00]))  # All Sound Off


def data_length(status: int) -> int:
    if 0x80 <= status <= 0xEF:
        return 1 if status & 0xE0 == 0xC0 else 2
    return {0xF1: 1, 0xF2: 2, 0xF3: 1}.get(status, 0)


class MidiParser:
    def __init__(
        self, output: WinMidiOut, sysex_mode: str = "pass", verbose: bool = True
    ):
        if sysex_mode not in ("pass", "drop"):
            raise ValueError(f"invalid SysEx mode: {sysex_mode}")
        self.output = output
        self.sysex_mode = sysex_mode
        self.verbose = verbose
        self.short_messages = 0
        self.sysex_passed = 0
        self.sysex_dropped = 0
        self.cleanup_next_channel = 0
        self.cleanup_complete = False
        self.status: int | None = None
        self.data = bytearray()
        self.sysex: bytearray | None = None

    def feed(self, value: int) -> None:
        if value >= 0xF8:
            self.emit(bytes([value]))
            return
        if self.sysex is not None:
            self.sysex.append(value)
            if value == 0xF7:
                message = bytes(self.sysex)
                self.sysex = None
                if self.sysex_mode == "pass":
                    self.output.sysex(message)
                    self.sysex_passed += 1
                    suffix = ""
                else:
                    self.sysex_dropped += 1
                    suffix = " [SysEx dropped]"
                if self.verbose:
                    print("MIDI " + message.hex(" ") + suffix, flush=True)
            return
        if value == 0xF0:
            self.status = None
            self.data.clear()
            self.sysex = bytearray([value])
            return
        if value & 0x80:
            self.data.clear()
            if value in (0xF4, 0xF5, 0xF7, 0xF9, 0xFD):
                self.status = None
                return
            length = data_length(value)
            if length == 0:
                self.emit(bytes([value]))
                self.status = None
            else:
                self.status = value
            return
        if self.status is None:
            return
        self.data.append(value)
        length = data_length(self.status)
        if len(self.data) == length:
            self.emit(bytes([self.status]) + bytes(self.data))
            self.data.clear()
            if self.status >= 0xF0:
                self.status = None

    def _is_cleanup_companion(self, message: bytes) -> bool:
        if len(message) != 3 or message[0] & 0xF0 != 0xB0 or message[2] != 0:
            return False
        channel = message[0] & 0x0F
        if message[1] == 0x40:
            return channel == self.cleanup_next_channel
        if message[1] == 0x78:
            return channel == self.cleanup_next_channel - 1
        return False

    def emit(self, message: bytes) -> None:
        self.output.short(message)
        self.short_messages += 1
        expected = bytes(
            [0xB0 + self.cleanup_next_channel, 0x7B, 0x00]
        )
        if message == expected:
            self.cleanup_next_channel += 1
            if self.cleanup_next_channel == 16:
                self.cleanup_complete = True
        elif message == bytes.fromhex("B0 7B 00"):
            self.cleanup_next_channel = 1
        elif self._is_cleanup_companion(message):
            pass  # CC64=0 before or CC120=0 after the channel's CC123 (#3)
        else:
            self.cleanup_next_channel = 0
        if self.verbose:
            print("MIDI " + message.hex(" "), flush=True)

    def summary(self) -> str:
        return (
            f"short={self.short_messages} sysex_passed={self.sysex_passed} "
            f"sysex_dropped={self.sysex_dropped}"
        )


def select_device(devices: list[tuple[int, str]], requested: str | None) -> tuple[int, str]:
    if requested is not None:
        if requested.isdigit():
            wanted = int(requested)
            for item in devices:
                if item[0] == wanted:
                    return item
        else:
            matches = [item for item in devices if requested.casefold() in item[1].casefold()]
            if len(matches) == 1:
                return matches[0]
            if len(matches) > 1:
                raise ValueError(f"device name is ambiguous: {requested}")
        raise ValueError(f"MIDI output device not found: {requested}")
    for needle in ("mt-32", "munt", "synth emulator"):
        for item in devices:
            if needle in item[1].casefold():
                return item
    raise ValueError("Munt MIDI output not found; use --list or --device")


def connect(host: str, port: int) -> socket.socket:
    while True:
        try:
            return socket.create_connection((host, port), timeout=0.5)
        except OSError:
            time.sleep(0.1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=15320)
    parser.add_argument("--device", help="MIDI output id or a unique part of its name")
    parser.add_argument(
        "--sysex",
        choices=("pass", "drop"),
        default="pass",
        help="forward SysEx normally or drop it for an A/B comparison",
    )
    parser.add_argument("--list", action="store_true", help="list MIDI outputs and exit")
    parser.add_argument(
        "--panic",
        action="store_true",
        help="silence every MIDI channel and exit",
    )
    parser.add_argument(
        "--quiet", action="store_true", help="suppress per-message logging"
    )
    parser.add_argument(
        "--stop-after-cleanup",
        action="store_true",
        help="exit after the ordered B0..BF cleanup (CC64/CC123/CC120 or CC123 only)",
    )
    args = parser.parse_args()

    devices = WinMidiOut.devices()
    if args.list:
        for device_id, name in devices:
            print(f"{device_id}: {name}")
        return 0
    try:
        device_id, name = select_device(devices, args.device)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    print(f"MIDI output: {device_id}: {name}", flush=True)
    with WinMidiOut(device_id) as output:
        if args.panic:
            send_panic(output)
            if not args.quiet:
                print("MIDI panic: all channels silenced", flush=True)
            return 0
        midi = MidiParser(output, sysex_mode=args.sysex, verbose=not args.quiet)
        while True:
            with connect(args.host, args.port) as connection:
                print(f"CSpect UART: connected to {args.host}:{args.port}", flush=True)
                connection.settimeout(None)
                while True:
                    try:
                        chunk = connection.recv(4096)
                    except (ConnectionError, OSError):
                        break
                    if not chunk:
                        break
                    for value in chunk:
                        midi.feed(value)
                        if args.stop_after_cleanup and midi.cleanup_complete:
                            print(f"MIDI summary: {midi.summary()}", flush=True)
                            print("MIDI cleanup: complete B0..BF All Notes Off", flush=True)
                            return 0
            print(f"MIDI summary: {midi.summary()}", flush=True)
            print("CSpect UART: disconnected; reconnecting", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
