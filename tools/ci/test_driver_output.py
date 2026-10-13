"""Checks SET_OUTPUT (#64) and the raw UART byte of STATUS (#17) in a Z80 simulator.

Uses the UART/NextReg model of compare_driver_builds.py. For each output
(Accelerator header, left and right joystick port) and a few values already in
NextReg $0B and $A2, checks QUERY, ACQUIRE, a WRITE, RELEASE and the errors.

    python3 tools/ci/test_driver_output.py --sjasmplus /tmp/sjasmplus/sjasmplus --skoolkit /tmp/skoolkit
"""
import argparse, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sjasmplus", default="sjasmplus")
    ap.add_argument("--skoolkit", default="/tmp/skoolkit")
    args = ap.parse_args()
    sys.path.insert(0, args.skoolkit)
    sys.path.insert(0, str(HERE))
    import compare_driver_builds as cdb
    from skoolkit.simulator import Simulator
    from skoolkit import simutils as su
    cdb.SJ = args.sjasmplus
    cdb.Simulator, cdb.su = Simulator, su
    img = cdb.assemble((REPO / "src/driver/mt32drv.s").read_text(), REPO / "include")

    fails = []
    cases = 0
    def check(cond, what):
        if not cond:
            fails.append(what)

    for choice, nr0b in ((0, 0x00), (1, 0xA1), (2, 0xB1)):
        for before_0b, before_a2 in ((0x00, 0x00), (0x80, 0x5A)):
            cases += 1
            tag = f"output {choice}, $0B={before_0b:02x} $A2={before_a2:02x}"
            mem = [0] * 65536
            mem[cdb.ORG:cdb.ORG + 512] = list(img)
            for i in range(16):
                mem[0xC000 + i] = 0x90 + i
            hw = cdb.Hw(100, [], 0)
            hw.nr[0x0b], hw.nr[0xa2] = before_0b, before_a2
            sim = Simulator(mem)
            sim.set_tracer(hw)
            r = sim.registers
            def call(fn, hl=0, de=0):
                cdb.call(sim, mem, hw, fn, hl, de)
                return r[su.F] & 1, r[su.A], r[su.B] * 256 + r[su.C], r[su.H], r[su.L]
            carry, *_ = call(7, 0, choice)
            check(carry == 0, f"{tag}: SET_OUTPUT failed")
            carry, a, bc, h, l = call(0)
            check(carry == 0 and bc == 0x4D54 and h == nr0b and l & 4, f"{tag}: QUERY H={h:02x} L={l:02x}")
            carry, *_ = call(1)
            check(carry == 0, f"{tag}: ACQUIRE failed")
            check(hw.nr[0x0b] == nr0b, f"{tag}: $0B={hw.nr[0x0b]:02x} while acquired")
            want_a2 = 0xD2 if choice == 0 else before_a2
            check(hw.nr[0xa2] == want_a2, f"{tag}: $A2={hw.nr[0xa2]:02x} while acquired")
            check(hw.nr[0xa0] & 0x30 == 0x30, f"{tag}: $A0 UART not enabled")
            hw.select = 0
            carry, a, bc, *_ = call(2, 0xC000, 16)
            check(carry == 0 and bc == 16 and hw.tx == [0x90 + i for i in range(16)], f"{tag}: WRITE")
            carry, *_ = call(7, 0, 0)            # change while acquired: next ACQUIRE
            check(carry == 0 and hw.nr[0x0b] == nr0b, f"{tag}: SET_OUTPUT while acquired")
            carry, *_ = call(5)
            check(carry == 0, f"{tag}: RELEASE failed")
            check(hw.nr[0x0b] == before_0b and hw.nr[0xa2] == before_a2 and hw.nr[0xa0] == 0x05,
                  f"{tag}: not restored ($0B={hw.nr[0x0b]:02x} $A2={hw.nr[0xa2]:02x} $A0={hw.nr[0xa0]:02x})")
            check(hw.nr_sel == 0x7f, f"{tag}: NextReg selector not restored")
            for bad in (3, 0x81, 0xff):
                carry, a, *_ = call(7, 0, bad)
                check(carry == 1 and a == 3, f"{tag}: SET_OUTPUT {bad:#x} not rejected")
            carry, a, bc, h, l = call(0)
            check(h == 0, f"{tag}: rejected value changed the output")
    # STATUS (#17): B is the raw UART status byte, error bits included.
    for extra in (0x00, 0x80, 0x40, 0x24, 0xE4):
        cases += 1
        mem = [0] * 65536
        mem[cdb.ORG:cdb.ORG + 512] = list(img)

        class ErrHw(cdb.Hw):
            def read_port(self, regs, port):
                v = super().read_port(regs, port)
                return v | extra if port == 0x133b and self.pi() else v

        hw = ErrHw(100, [0x55], 0)
        sim = Simulator(mem)
        sim.set_tracer(hw)
        r = sim.registers
        cdb.call(sim, mem, hw, 1)
        cdb.call(sim, mem, hw, 3)
        want = 0x01 | 0x10 | extra        # RX data, TX empty, injected bits
        check(r[su.F] & 1 == 0 and r[su.B] == want and r[su.C] == 0x0D,
              f"STATUS with ${extra:02x}: B={r[su.B]:02x} C={r[su.C]:02x}")
    for f in fails:
        print("FAIL", f)
    print(f"{cases} cases, {len(fails)} failures")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
