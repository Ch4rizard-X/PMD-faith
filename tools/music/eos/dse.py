"""Minimal Procyon DSE (SWDL/SMDL v0x415) parser for PMD: Explorers of Sky."""
import struct

U8 = lambda d, o: d[o]
S8 = lambda d, o: struct.unpack_from('<b', d, o)[0]
U16 = lambda d, o: struct.unpack_from('<H', d, o)[0]
S16 = lambda d, o: struct.unpack_from('<h', d, o)[0]
U32 = lambda d, o: struct.unpack_from('<I', d, o)[0]


def find_chunks(d, start=0x50):
    chunks = {}
    o = start
    while o + 16 <= len(d):
        lab = d[o:o + 4]
        ln = U32(d, o + 0xC)
        chunks[lab.decode('latin1')] = (o + 0x10, ln)
        if lab == b'eod ':
            break
        o = o + 0x10 + ln
        o = (o + 15) & ~15 if False else o
        while o % 4:
            o += 1
        # skip padding bytes until a plausible chunk label
        while o + 4 <= len(d) and d[o:o + 4] not in (b'wavi', b'prgi', b'kgrp', b'pcmd', b'eod ', b'song', b'trk ') and d[o] in (0, 0x98, 0xAA, 0xFF):
            o += 4
    return chunks


class Wav:
    pass


class Split:
    pass


class Program:
    pass


class SWD:
    def __init__(self, path):
        d = open(path, 'rb').read()
        self.d = d
        assert d[:4] == b'swdl', path
        self.version = U16(d, 0xC)
        self.pcmdlen = U32(d, 0x40)
        self.nbwavi = U16(d, 0x46)
        self.nbprgi = U16(d, 0x48)
        self.chunks = find_chunks(d)
        self.wavs = {}
        self.programs = {}
        self.pcm = None
        if 'wavi' in self.chunks:
            base, ln = self.chunks['wavi']
            for i in range(self.nbwavi):
                off = U16(d, base + 2 * i)
                if off == 0 and i != 0:
                    continue
                if off == 0:
                    # slot 0 with zero offset is only valid if the table is followed by data at 0
                    continue
                self.wavs[i] = self._wav(base + off)
        if 'prgi' in self.chunks:
            base, ln = self.chunks['prgi']
            for i in range(self.nbprgi):
                off = U16(d, base + 2 * i)
                if off == 0:
                    continue
                self.programs[i] = self._prg(base + off)
        if 'kgrp' in self.chunks:
            base, ln = self.chunks['kgrp']
            self.kgrps = []
            for o in range(base, base + ln, 8):
                self.kgrps.append(dict(id=U16(d, o), poly=S8(d, o + 2), prio=U8(d, o + 3), lo=U8(d, o + 4), hi=U8(d, o + 5)))
        if 'pcmd' in self.chunks:
            self.pcm = self.chunks['pcmd']

    def _wav(self, o):
        d = self.d
        w = Wav()
        w.id = U16(d, o + 2)
        w.ftune = S8(d, o + 4)
        w.ctune = S8(d, o + 5)
        w.rootkey = U8(d, o + 6)
        w.ktps = S8(d, o + 7)
        w.vol = U8(d, o + 8)
        w.pan = U8(d, o + 9)
        w.fmt = U16(d, o + 0x12)
        w.loop = U8(d, o + 0x15)
        w.smplrate = U32(d, o + 0x20)
        w.smplpos = U32(d, o + 0x24)
        w.loopbeg = U32(d, o + 0x28)
        w.looplen = U32(d, o + 0x2C)
        w.envon = U8(d, o + 0x30)
        w.envmult = U8(d, o + 0x31)
        (w.atkvol, w.attack, w.decay, w.sustain, w.hold, w.decay2, w.release) = d[o + 0x38:o + 0x3F]
        w.raw = d[o:o + 64]
        return w

    def _prg(self, o):
        d = self.d
        p = Program()
        p.id = U16(d, o)
        nsplits = U16(d, o + 2)
        p.vol = U8(d, o + 4)
        p.pan = U8(d, o + 5)
        p.unk3 = U8(d, o + 6)
        p.poly = U8(d, o + 7)
        nlfo = U8(d, o + 0xB)
        p.lfos = []
        q = o + 16
        for i in range(nlfo):
            r = d[q:q + 16]
            p.lfos.append(dict(unk34=r[0], unk52=r[1], dest=r[2], wshape=r[3], rate=U16(r, 4), unk29=U16(r, 6),
                               depth=U16(r, 8), delay=U16(r, 10), unk32=U16(r, 12), unk33=U16(r, 14), raw=r))
            q += 16
        q += 16
        p.splits = []
        for i in range(nsplits):
            s = Split()
            s.id = U8(d, q + 1)
            s.bendrange = U8(d, q + 2)
            s.lowkey = S8(d, q + 4)
            s.hikey = S8(d, q + 5)
            s.lovel = S8(d, q + 8)
            s.hivel = S8(d, q + 9)
            s.smplid = U16(d, q + 0x12)
            s.ftune = S8(d, q + 0x14)
            s.ctune = S8(d, q + 0x15)
            s.rootkey = S8(d, q + 0x16)
            s.ktps = S8(d, q + 0x17)
            s.vol = U8(d, q + 0x18)
            s.pan = U8(d, q + 0x19)
            s.kgrp = U8(d, q + 0x1A)
            s.envon = U8(d, q + 0x20)
            s.envmult = U8(d, q + 0x21)
            (s.atkvol, s.attack, s.decay, s.sustain, s.hold, s.decay2, s.release) = d[q + 0x28:q + 0x2F]
            s.raw = d[q:q + 48]
            p.splits.append(s)
            q += 48
        return p


FIXED_RESTS = [96, 72, 64, 48, 36, 32, 24, 18, 16, 12, 9, 8, 6, 4, 3, 2]
ARGLEN = {}
for c in (0x9D, 0xB0, 0xC0, 0x90, 0x98, 0x99):
    ARGLEN[c] = 0
for c in (0x9C, 0xA9, 0xAA, 0xB1, 0xB2, 0xB3, 0xB5, 0xB6, 0xBC, 0xBE, 0xBF, 0xC3, 0xD0, 0xD1, 0xD2, 0xDB, 0xDF,
          0xE1, 0xE7, 0xE9, 0xEF, 0xF6, 0xA0, 0xA1, 0xA4, 0xA5, 0xAB, 0xAC, 0xE0, 0xE3, 0xE8, 0x91, 0x92, 0x95):
    ARGLEN[c] = 1
for c in (0xA8, 0xB4, 0xD3, 0xD5, 0xD6, 0xD8, 0xF2, 0xCB, 0xF8, 0xD7, 0x93):
    ARGLEN[c] = 2
for c in (0xAF, 0xD4, 0xE2, 0xEA, 0xF3, 0x94):
    ARGLEN[c] = 3
for c in (0xDD, 0xE5, 0xED, 0xF1):
    ARGLEN[c] = 4
for c in (0xDC, 0xE4, 0xEC, 0xF0):
    ARGLEN[c] = 5


class Track:
    pass


class SMD:
    def __init__(self, path):
        d = open(path, 'rb').read()
        self.d = d
        assert d[:4] == b'smdl'
        self.version = U16(d, 0xC)
        o = 0x40
        assert d[o:o + 4] == b'song'
        self.song_raw = d[o:o + 0x40]
        self.tpqn = U16(d, o + 0x12)
        self.nbtrks = U8(d, o + 0x16)
        self.nbchans = U8(d, o + 0x17)
        o += 0x40
        self.tracks = []
        while o + 16 <= len(d) and d[o:o + 4] == b'trk ':
            ln = U32(d, o + 0xC)
            t = Track()
            t.start = o + 0x10
            t.trkid = d[o + 0x10]
            t.chan = d[o + 0x11]
            t.ev_start = o + 0x14
            t.ev_end = o + 0x10 + ln
            self.tracks.append(t)
            o = o + 0x10 + ln
            while o % 4:
                o += 1


def parse_track_events(d, t):
    """Yield (offset, cmd, args) for a track, stopping at 0x98."""
    o = t.ev_start
    out = []
    while o < t.ev_end:
        c = d[o]
        if c < 0x80:
            a = d[o + 1]
            n = (a >> 6) & 3
            args = bytes(d[o + 1:o + 2 + n])
            out.append((o, c, args))
            o += 2 + n
            continue
        if c < 0x90:
            out.append((o, c, b''))
            o += 1
            continue
        if c not in ARGLEN:
            out.append((o, c, None))  # unknown -> stop
            break
        n = ARGLEN[c]
        out.append((o, c, bytes(d[o + 1:o + 1 + n])))
        o += 1 + n
        if c == 0x98:
            break
    return out
