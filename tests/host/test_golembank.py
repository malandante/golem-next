from __future__ import annotations

import io
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "tools" / "host"
sys.path.insert(0, str(TOOLS))

import golembank  # noqa: E402
from golembank import BankError, Instrument, WoplFile, put_instrument, read_sbi, read_wopl, write_wopl  # noqa: E402


def sbi(name: bytes = b"Test", regs: bytes = bytes(range(0x11, 0x1C))) -> bytes:
    return b"SBI\x1a" + name.ljust(32, b"\0") + regs + bytes(5)


class WoplTests(unittest.TestCase):
    def test_empty_bank_layout(self) -> None:
        data = write_wopl(WoplFile())
        self.assertTrue(data.startswith(b"WOPL3-BANK\0"))
        self.assertEqual(struct.unpack_from("<H", data, 11)[0], 3)
        self.assertEqual(struct.unpack_from(">HH", data, 13), (1, 1))
        # header, two bank entries, 256 instruments of 66 bytes
        self.assertEqual(len(data), 19 + 2 * 34 + 256 * 66)
        back = read_wopl(data)
        self.assertTrue(all(ins.blank for ins in back.melodic[0].instruments))
        self.assertEqual(write_wopl(back), data)

    def test_round_trip_keeps_everything(self) -> None:
        wopl = WoplFile(opl_flags=0x02, volume_model=3)
        wopl.melodic[0].name = "Golem"
        wopl.melodic[0].msb = 5
        ins = read_sbi(sbi())
        ins.note_offset1 = -12
        ins.velocity_offset = -3
        ins.delay_on_ms = 1200
        put_instrument(wopl, ins, program=7)
        data = write_wopl(wopl)
        back = read_wopl(data)
        self.assertEqual(back.opl_flags, 0x02)
        self.assertEqual(back.volume_model, 3)
        self.assertEqual((back.melodic[0].name, back.melodic[0].msb), ("Golem", 5))
        self.assertEqual(back.melodic[0].instruments[7], ins)
        self.assertEqual(write_wopl(back), data)

    def test_woplx_block_is_kept(self) -> None:
        block = b"GLMX" + bytes([0, 1]) + bytes(4) + bytes([0xDE, 0xAD, 0xBE, 0xEF])
        data = write_wopl(WoplFile()) + block
        wopl = read_wopl(data)
        self.assertEqual(wopl.extension, block)
        put_instrument(wopl, read_sbi(sbi()), program=0)
        self.assertTrue(write_wopl(wopl).endswith(block))
        self.assertIn("WOPLX", golembank.describe(wopl))

    def test_bad_files(self) -> None:
        with self.assertRaises(BankError):
            read_wopl(b"WOPL2-BANK\0" + bytes(20))
        with self.assertRaises(BankError):
            read_wopl(write_wopl(WoplFile())[:-1])
        with self.assertRaises(BankError):
            read_sbi(b"4OP\x1a" + bytes(60))
        with self.assertRaises(BankError):
            read_sbi(b"SBI\x1a" + bytes(20))


class SbiTests(unittest.TestCase):
    def test_registers_go_to_the_right_operators(self) -> None:
        # 20 mod/car, 40 mod/car, 60 mod/car, 80 mod/car, E0 mod/car, C0
        regs = bytes([0x21, 0x31, 0x4F, 0x00, 0xF2, 0xF3, 0x53, 0x74, 0x01, 0x02, 0x0E])
        ins = read_sbi(sbi(b"Bright Piano", regs))
        carrier, modulator = ins.operators[0], ins.operators[1]
        self.assertEqual((carrier.avekf_20, carrier.ksl_l_40, carrier.atdec_60, carrier.susrel_80,
                          carrier.waveform_e0), (0x31, 0x00, 0xF3, 0x74, 0x02))
        self.assertEqual((modulator.avekf_20, modulator.ksl_l_40, modulator.atdec_60, modulator.susrel_80,
                          modulator.waveform_e0), (0x21, 0x4F, 0xF2, 0x53, 0x01))
        self.assertEqual(ins.fb_conn1, 0x0E)
        self.assertEqual(ins.flags, 0)  # 2-operator, not blank
        self.assertEqual(ins.name, "Bright Piano")

    def test_drum_key(self) -> None:
        wopl = WoplFile()
        put_instrument(wopl, read_sbi(sbi()), drum=36)
        self.assertEqual(wopl.percussion[0].instruments[36].percussion_key, 36)
        put_instrument(wopl, read_sbi(sbi()), drum=38, key=60)
        self.assertEqual(wopl.percussion[0].instruments[38].percussion_key, 60)
        with self.assertRaises(BankError):
            put_instrument(wopl, Instrument(), program=128)


class CommandLineTests(unittest.TestCase):
    def run_main(self, *args: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = golembank.main(list(args))
        return code, out.getvalue() + err.getvalue()

    def test_new_add_list(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bank = Path(tmp) / "bank.wopl"
            piano = Path(tmp) / "piano.sbi"
            piano.write_bytes(sbi(b"Piano"))
            self.assertEqual(self.run_main("new", str(bank), "--name", "Mine")[0], 0)
            self.assertEqual(self.run_main("add", str(bank), str(piano), "--program", "0")[0], 0)
            self.assertEqual(self.run_main("add", str(bank), str(piano), "--drum", "36", "--name", "Kick")[0], 0)
            code, text = self.run_main("list", str(bank))
            self.assertEqual(code, 0)
            self.assertIn("0 Piano [2-op]", text)
            self.assertIn("36 Kick [2-op, key 36]", text)
            code, text = self.run_main("new", str(bank))
            self.assertEqual(code, 1)
            self.assertIn("already exists", text)


if __name__ == "__main__":
    unittest.main()
