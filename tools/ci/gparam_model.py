"""A model of the Golem's sound-parameter protocol (docs/sound-params.md), as
the firmware's src/golem/params.cpp implements it, for the simulator tests of
src/lib/gparam.s and .GPARAM. The engine behind it is plain bytes: area 10
(128 settings, writable 00-1F, values up to 100), area 01 (programs 0-15 of
melodic bank 0) and the WOPL BLOB kept as given."""

HEADER = [0xF0, 0x7D, 0x47, 0x4C, 0x4D, 0x01]


def checksum(data):
    return (128 - (sum(data) & 0x7F)) & 0x7F


def pack(data):
    out = []
    for i in range(0, len(data), 7):
        g = data[i:i + 7]
        out.append(sum(((b >> 7) & 1) << j for j, b in enumerate(g)))
        out.extend(b & 0x7F for b in g)
    return out


def unpack(data):
    out, i = [], 0
    while i < len(data):
        hi, g = data[i], data[i + 1:i + 8]
        if not g:
            return None
        out.extend(b | (((hi >> j) & 1) << 7) for j, b in enumerate(g))
        i += 1 + len(g)
    return out


def get21(p):
    return p[0] << 14 | p[1] << 7 | p[2]


def put21(n):
    return [(n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F]


def put14(n):
    return [n & 0x7F, (n >> 7) & 0x7F]


class ModelGolem:

    def __init__(self, info_name="model golem"):
        self.out = bytearray()
        self.rx = []
        self.settings = [0] * 128
        self.instr = {p: [(p * 3 + i) & 0x7F for i in range(128)] for p in range(16)}
        self.blob = bytes(b"WOPL3-BANK\0" + bytes(range(256)) * 4)
        self.mt32 = bytes()          # BLOB type 04: the MT-32 dump
        self.fx = bytes()            # BLOB type 03: the effects profile
        self.blob_types = []         # type of each BLOB begun or read
        self.upload = None
        self.silent = False
        self.name = info_name
        self.frames = []

    def receive(self, data):
        for b in data:
            if b == 0xF0:
                self.rx = [b]
            elif self.rx:
                self.rx.append(b)
                if b == 0xF7:
                    self.frames.append(bytes(self.rx))
                    if not self.silent:
                        self.handle(self.rx)
                    self.rx = []

    def reply(self, tt, resp, cc, payload, cs):
        f = HEADER + [tt, resp, cc] + [b & 0x7F for b in payload]
        if cs:
            f.append(checksum(payload))
        self.out += bytes(f + [0xF7])

    def fail(self, tt, cc, code, detail=0x3FFF):
        self.reply(tt, 0x42, cc, [code] + put14(min(detail, 0x3FFF)), False)

    def handle(self, f):
        if list(f[:6]) != HEADER or len(f) < 10:
            return                  # music SysEx and the like: not for the protocol
        tt, cc = f[6], f[7]
        body = f[8:-1]
        if (sum(body) & 0x7F) != 0:
            return self.fail(tt, cc, 0x07)
        flags, p = body[0], body[1:-1]
        if cc == 0x07:
            if p == [0]:
                out = [0, 1, 1, 0, 1, 3, 0, 4] + put14(0x35) + put14(1000) + put14(256) + [4, 1, 6, 0] + put14(0) + [79]
            elif p == [1]:
                out = [1] + list(self.name.encode())
            else:
                return self.fail(tt, cc, 0x04, 0)
            return self.reply(tt, 0x44, cc, out, True)
        if cc == 0x08:
            area, addr, data = p[0], get21(p[1:4]), p[4:]
            if area == 0x10:
                if addr + len(data) > 0x20:
                    return self.fail(tt, cc, 0x08, max(0, 0x20 - addr))
                for i, b in enumerate(data):
                    if b > 100:
                        return self.fail(tt, cc, 0x04, i)
                self.settings[addr:addr + len(data)] = data
            elif area == 0x01:
                prog, off = addr >> 7, addr & 0x7F
                if prog not in self.instr or off + len(data) > 128:
                    return self.fail(tt, cc, 0x08, 0)
                self.instr[prog][off:off + len(data)] = data
            else:
                return self.fail(tt, cc, 0x08, 0)
            if flags & 1:
                self.reply(tt, 0x41, cc, [], False)
            return
        if cc == 0x09:
            area, addr, n = p[0], get21(p[1:4]), p[4] | p[5] << 7
            if area == 0x10:
                if addr + n > 128:
                    return self.fail(tt, cc, 0x08)
                data = self.settings[addr:addr + n]
            elif area == 0x01:
                prog, off = addr >> 7, addr & 0x7F
                if prog not in self.instr or off + n > 128:
                    return self.fail(tt, cc, 0x08)
                data = self.instr[prog][off:off + n]
            else:
                return self.fail(tt, cc, 0x08)
            return self.reply(tt, 0x45, cc, p[:4] + data, True)
        if cc == 0x0C:
            op, q = p[0], p[1:]
            if op == 0:
                self.upload = {"size": get21(q[2:5]), "data": [], "seq": 0, "type": q[0]}
                self.blob_types.append(q[0])
                return self.reply(tt, 0x41, cc, [0], False)
            if op == 1:
                seq = q[0] | q[1] << 7
                if not self.upload or seq != self.upload["seq"]:
                    return self.fail(tt, cc, 0x0B, 1)
                chunk = unpack(q[2:])
                self.upload["data"] += chunk
                self.upload["seq"] += 1
                if flags & 1:
                    self.reply(tt, 0x41, cc, [1] + put14(seq), False)
                return
            if op == 2:
                if not self.upload or len(self.upload["data"]) != self.upload["size"]:
                    return self.fail(tt, cc, 0x0B)
                self.reply(tt, 0x40, cc, [], False)
                if self.upload["type"] == 4:
                    self.mt32 = bytes(self.upload["data"])
                elif self.upload["type"] == 3:
                    self.fx = bytes(self.upload["data"])
                else:
                    self.blob = bytes(self.upload["data"])
                self.upload = None
                return self.reply(tt, 0x41, cc, [2], False)
            if op == 4:
                pos, n = get21(q[2:5]), q[5] | q[6] << 7
                blob = self.mt32 if q[0] == 4 else self.fx if q[0] == 3 else self.blob
                if pos == 0:
                    self.blob_types.append(q[0])
                if n == 0:
                    return self.reply(tt, 0x45, cc, [4] + put21(len(blob)), True)
                part = list(blob[pos:pos + n])
                return self.reply(tt, 0x45, cc, [4] + put21(pos) + pack(part), True)
        return self.fail(tt, cc, 0x03)

    def take(self, n):
        data = self.out[:n]
        del self.out[:n]
        return data
