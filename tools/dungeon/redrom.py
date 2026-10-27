"""Minimal PMD Red ROM reader: pksdir archives, AT3PX/AT4PX decompression (decompress_at.c), SIRO deref."""
import struct
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common
ROM_PATH = os.path.join(common.PMDRED, 'baserom.gba')
_rom = None

def rom():
    global _rom
    if _rom is None:
        _rom = open(ROM_PATH, 'rb').read()
    return _rom

def off(addr):
    return addr - 0x08000000

def u32(o):
    return struct.unpack_from('<I', rom(), o)[0]

def cstr(o):
    r = rom(); e = r.index(b'\0', o)
    return r[o:e].decode('latin1')

class Archive:
    def __init__(self, addr):
        o = off(addr)
        assert rom()[o:o + 7] == b'pksdir0'
        n = u32(o + 8); t = off(u32(o + 12))
        self.files = {}
        for i in range(n):
            name = cstr(off(u32(t + i * 8)))
            self.files[name] = off(u32(t + i * 8 + 4))

    def raw(self, name):
        """offset of file data after SIRO deref (like OpenFileAndGetFileDataPtr)."""
        o = self.files[name]
        if rom()[o:o + 4] in (b'SIRO', b'SIR0'):
            return off(u32(o + 4))
        return o

DUNGEON = 0x083B0000

def dungeon():
    return Archive(DUNGEON)

def at_decompress(o):
    src = rom()
    assert src[o:o + 2] == b'AT', src[o:o + 5]
    clen = src[o + 5] | (src[o + 6] << 8)
    if src[o + 2:o + 4] == b'4P':
        idx = 0x12
    else:
        idx = 0x10
    if src[o + 4] == ord('N'):
        return bytes(src[o + 7:o + 7 + clen])
    flags = [src[o + 7 + i] + 3 for i in range(9)]
    dst = bytearray()
    cur = idx; cmd_bit = 8; byte = 0
    while cur < clen:
        if cmd_bit == 8:
            byte = src[o + cur]; cur += 1; cmd_bit = 0
        if byte & 0x80 == 0:
            b = src[o + cur]
            command = (b >> 4) + 3
            tmp = (b & 0xF) << 8
            for k, f in enumerate(flags):
                if command == f:
                    command = 0x1F - k
            c = b & 0xF
            def P(a, bb):
                dst.append(((a & 0xF) << 4) | (bb & 0xF))
            if command == 0x1F:
                cur += 1; P(c, c); P(c, c)
            elif command == 0x1E:
                cur += 1; P(c, c + 1); P(c + 1, c + 1)
            elif command == 0x1D:
                cur += 1; P(c, c - 1); P(c, c)
            elif command == 0x1C:
                cur += 1; P(c, c); P(c - 1, c)
            elif command == 0x1B:
                cur += 1; P(c, c); P(c, c - 1)
            elif command == 0x1A:
                cur += 1; P(c, c - 1); P(c - 1, c - 1)
            elif command == 0x19:
                cur += 1; P(c, c + 1); P(c, c)
            elif command == 0x18:
                cur += 1; P(c, c); P(c + 1, c)
            elif command == 0x17:
                cur += 1; P(c, c); P(c, c + 1)
            else:
                tmp += src[o + cur + 1]; cur += 2
                tmp += len(dst) - 0x1000
                for _ in range(command):
                    dst.append(dst[tmp]); tmp += 1
        else:
            dst.append(src[o + cur]); cur += 1
        cmd_bit += 1
        byte = (byte << 1) & 0xFF
    return bytes(dst)

def rgb_list(o, n):
    r = rom()
    return [(r[o + i * 4], r[o + i * 4 + 1], r[o + i * 4 + 2]) for i in range(n)]
