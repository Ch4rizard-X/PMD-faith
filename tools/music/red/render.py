#!/usr/bin/env python3
"""GBA MP2K (m4a / "Sappy") software renderer for the pmd-red decompilation.

Usage: python3 render.py NNN out.wav [--tail SECONDS]

Renders song NNN (sound/songs/seq_NNN.s) at 44100 Hz stereo: intro + loop played
twice (GOTO followed once more), plus a short tail, and prints JSON with the
loop start / loop end times (seconds) of track 0.

The sequencer, channel allocation, envelopes and pitch maths follow the engine
code in pmd-red's src/m4a_1.s / src/m4a.c (MPlayMain, ply_note, TrkVolPitSet,
ChnVolSetAsm, SoundMainRAM envelope, CgbSound) as closely as is practical:
 - 60 Hz (59.7275 Hz) frame loop; tempo accumulator += BPM per frame, tick per 150
 - 5 DirectSound channels (m4aSoundMode MAXCHN=5) with m4a priority stealing
 - 4 CGB channels (sq1, sq2, wave, noise), one voice each, software envelope
 - per-frame DirectSound ADSR in MP2K units, master volume 14/15
 - m4a reverb (feedback from 4 and 5 frames back, rev/512)
"""
import json
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import common  # noqa: E402
ROOT = os.environ.get('PMD_ROOT', common.PMDRED)
OUT_RATE = 44100
# Nominal 60 Hz frame rate (tick rate = BPM*24/60 /s); real hardware is 59.7275 Hz,
# the shipped rips (and the app's loop markers) use 60 Hz.
FRAME_RATE = float(os.environ.get("M4A_FRAME_RATE", "60.0"))
MIX_RATE = 304 * FRAME_RATE                 # m4a 18157 Hz mixer (DirectSoundFix rate)
MAX_PCM = 5                                 # m4aSoundMode(... 5 << MAXCHN_SHIFT)
MASTER_VOL = 14                             # m4aSoundMode(... 14 << MASVOL_SHIFT)
# Amplitude of a CGB channel at envelope 15, relative to a full-scale (s8 = +-128)
# DirectSound mix.  GBA: PSG 0..15 <<3 * (master 7 + 1) >> 2 -> 0..240 (+-120)
# against DMA s8 << 2 (+-512) => ~0.234.
WAVE_GAIN = float(os.environ.get('WAVE_GAIN', '2.0'))   # calibrated vs rips (+6 dB)
INTERP = os.environ.get('M4A_INTERP', '1') == '1'
ZOH = os.environ.get('M4A_ZOH', '0') == '1'
WIDTH = float(os.environ.get('M4A_WIDTH', '0.5'))      # rips are much narrower than raw m4a pan
CGB_AMP = float(os.environ.get('CGB_AMP', '0.234'))

# --------------------------------------------------------------------------- assembler
_ident = re.compile(r'[A-Za-z_][A-Za-z_0-9]*')


class Asm:
    """Tiny GAS subset: .equ/.set, labels, .byte/.hword/.word, .align."""

    def __init__(self, syms=None):
        self.syms = dict(syms or {})
        self.labels = {}
        self.data = bytearray()
        self.words = {}      # offset -> symbolic word expression (unresolved)

    def eval(self, expr, allow_unknown=False):
        expr = expr.strip()
        unknown = []

        def rep(m):
            n = m.group(0)
            if n in self.syms:
                return '(%d)' % self.syms[n]
            if n in self.labels:
                return '(%d)' % self.labels[n]
            unknown.append(n)
            return '0'
        e = _ident.sub(lambda m: m.group(0) if re.fullmatch(r'0[xX][0-9a-fA-F]+', m.group(0)) else rep(m),
                       re.sub(r'0[xX][0-9a-fA-F]+', lambda m: str(int(m.group(0), 16)), expr))
        if unknown:
            if allow_unknown:
                return None
            raise KeyError('unknown symbol(s) %s in %r' % (unknown, expr))
        e = e.replace('/', '//')
        return int(eval(e, {'__builtins__': {}}, {}))

    @staticmethod
    def lines(path):
        out = []
        with open(path) as f:
            for raw in f:
                line = raw.split('@', 1)[0].strip()
                if line:
                    out.append(line)
        return out

    def load_equs(self, path):
        for line in self.lines(path):
            m = re.match(r'\.(equ|set|equiv)\s+([A-Za-z_0-9]+)\s*,\s*(.+)$', line)
            if m:
                self.syms[m.group(2)] = self.eval(m.group(3))

    def assemble(self, paths):
        # pass 1: sizes and labels; pass 2: data
        for pas in (1, 2):
            off = 0
            if pas == 2:
                self.data = bytearray()
            for path in paths:
                for line in self.lines(path):
                    while True:
                        m = re.match(r'([A-Za-z_][A-Za-z_0-9]*):\s*(.*)$', line)
                        if not m:
                            break
                        if pas == 1:
                            self.labels[m.group(1)] = off
                        line = m.group(2)
                    if not line:
                        continue
                    m = re.match(r'(\.[a-z]+)\s*(.*)$', line)
                    if not m:
                        raise ValueError('cannot parse %r in %s' % (line, path))
                    d, arg = m.group(1), m.group(2)
                    if d in ('.equ', '.set', '.equiv'):
                        n, v = arg.split(',', 1)
                        val = self.eval(v, allow_unknown=True)
                        if val is not None:
                            self.syms[n.strip()] = val
                        else:
                            self.syms.setdefault('__sym_' + n.strip(), 0)
                            self.symtext = getattr(self, 'symtext', {})
                            self.symtext[n.strip()] = v.strip()
                    elif d in ('.byte', '.hword', '.word'):
                        size = {'.byte': 1, '.hword': 2, '.word': 4}[d]
                        items = [a for a in arg.split(',') if a.strip()]
                        for a in items:
                            if pas == 2:
                                v = self.eval(a, allow_unknown=True)
                                if v is None:
                                    self.words[off] = a.strip()
                                    v = 0
                                self.data += int(v & ((1 << (8 * size)) - 1)).to_bytes(size, 'little')
                            off += size
                    elif d == '.align':
                        n = 1 << int(arg.split(',')[0])
                        pad = (-off) % n
                        if pas == 2:
                            self.data += bytes(pad)
                        off += pad
                    elif d in ('.include', '.section', '.global', '.end', '.text', '.balign'):
                        pass
                    else:
                        raise ValueError('unknown directive %s' % d)
        return self


_base_syms = None


def base_syms():
    global _base_syms
    if _base_syms is None:
        a = Asm()
        a.load_equs(os.path.join(ROOT, 'MPlayDef.s'))
        a.load_equs(os.path.join(ROOT, 'VoiceDef.s'))
        _base_syms = a.syms
    return _base_syms


# --------------------------------------------------------------------------- data
class Wave:
    def __init__(self, name):
        a = Asm(base_syms()).assemble([os.path.join(ROOT, 'sound/wave/%s.s' % name)])
        d = a.data
        self.flags = int.from_bytes(d[2:4], 'little')
        self.loop = bool(self.flags & 0xC000)
        self.freq = int.from_bytes(d[4:8], 'little')
        self.loop_start = int.from_bytes(d[8:12], 'little')
        self.size = int.from_bytes(d[12:16], 'little')
        pcm = np.frombuffer(bytes(d[16:]), dtype=np.int8).astype(np.float32)
        n = self.size
        if len(pcm) < n + 1:
            pcm = np.concatenate([pcm, np.zeros(n + 1 - len(pcm), np.float32)])
        pcm = pcm[:n + 1].copy()
        if self.loop and n > self.loop_start:
            pcm[n] = pcm[self.loop_start]        # interpolation partner at the wrap
        self.pcm = pcm


class GbWave:
    def __init__(self, name):
        a = Asm(base_syms()).assemble([os.path.join(ROOT, 'sound/wave/%s.s' % name)])
        nib = []
        for b in a.data[:16]:
            nib += [b >> 4, b & 15]
        self.samples = np.array(nib, dtype=np.float32)


class Tone:
    __slots__ = ('type', 'key', 'length', 'pan_sweep', 'wav', 'sub', 'keymap',
                 'attack', 'decay', 'sustain', 'release', 'name')


class VoiceBank:
    """All voicegroups/keymaps assembled as one contiguous blob (sound/voice_groups.inc order),
    so keysplit tables / drum tables that index past their m4a2s split behave like the ROM."""

    def __init__(self):
        inc = os.path.join(ROOT, 'sound/voice_groups.inc')
        files = [os.path.join(ROOT, m) for m in re.findall(r'\.include\s+"([^"]+)"', open(inc).read())]
        self.asm = Asm(base_syms()).assemble(files)
        self.waves = {}
        self.gbwaves = {}
        self.cache = {}

    def wave(self, name):
        if name not in self.waves:
            self.waves[name] = Wave(name)
        return self.waves[name]

    def gbwave(self, name):
        if name not in self.gbwaves:
            self.gbwaves[name] = GbWave(name)
        return self.gbwaves[name]

    def tone_at(self, off):
        if off in self.cache:
            return self.cache[off]
        d, w = self.asm.data, self.asm.words
        t = Tone()
        t.type, t.key, t.length, t.pan_sweep = d[off], d[off + 1], d[off + 2], d[off + 3]
        wsym = w.get(off + 4)
        wnum = int.from_bytes(d[off + 4:off + 8], 'little')
        t.attack, t.decay, t.sustain, t.release = d[off + 8], d[off + 9], d[off + 10], d[off + 11]
        t.wav = t.sub = t.keymap = None
        t.name = wsym
        if t.type & 0xC0:
            t.sub = self.asm.labels[wsym] if wsym else wnum
            if t.type & 0x40:
                km = w.get(off + 8)
                t.keymap = self.asm.labels[km] if km else int.from_bytes(d[off + 8:off + 12], 'little')
        elif (t.type & 7) == 0:
            t.wav = self.wave(wsym)
        elif (t.type & 7) == 3:
            t.wav = self.gbwave(wsym)
        else:
            t.wav = wnum          # duty / noise width
        self.cache[off] = t
        return t

    def tone(self, group_off, idx):
        return self.tone_at(group_off + 12 * idx)

    def keymap(self, off, key):
        return self.asm.data[off + key]


class Song:
    def __init__(self, num):
        self.num = num
        path = os.path.join(ROOT, 'sound/songs/seq_%03d.s' % num)
        a = Asm(base_syms()).assemble([path])
        self.asm = a
        self.data = a.data
        hdr = a.labels['seq_%03d' % num]
        d = self.data
        self.ntracks = d[hdr]
        self.priority = d[hdr + 2]
        self.reverb = d[hdr + 3]
        self.group = a.symtext['seq_%03d_grp' % num]
        self.tracks = [int.from_bytes(d[hdr + 8 + 4 * i: hdr + 12 + 4 * i], 'little')
                       for i in range(self.ntracks)]


# --------------------------------------------------------------------------- engine
SCALE = [0xE0 - 0x10 * (k // 12) + (k % 12) for k in range(180)]
FREQ_TABLE = [2147483648, 2275179671, 2410468894, 2553802834, 2705659852, 2866546760,
              3037000500, 3217589947, 3408917802, 3611622603, 3826380858, 4053909305]
CGB_FREQ = [-2004, -1891, -1785, -1685, -1591, -1501, -1417, -1337, -1262, -1192, -1125, -1062]
NOISE_TABLE = [0xD7, 0xD6, 0xD5, 0xD4, 0xC7, 0xC6, 0xC5, 0xC4, 0xB7, 0xB6, 0xB5, 0xB4,
               0xA7, 0xA6, 0xA5, 0xA4, 0x97, 0x96, 0x95, 0x94, 0x87, 0x86, 0x85, 0x84,
               0x77, 0x76, 0x75, 0x74, 0x67, 0x66, 0x65, 0x64, 0x57, 0x56, 0x55, 0x54,
               0x47, 0x46, 0x45, 0x44, 0x37, 0x36, 0x35, 0x34, 0x27, 0x26, 0x25, 0x24,
               0x17, 0x16, 0x15, 0x14, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00]
CGB3_VOL = [0, 0, .25, .25, .25, .25, .5, .5, .5, .5, .75, .75, .75, .75, 1, 1]
CLOCK = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
         24, 28, 30, 32, 36, 40, 42, 44, 48, 52, 54, 56, 60, 64, 66, 68, 72, 76, 78, 80, 84, 88,
         90, 92, 96]
DUTY = {0: 0.125, 1: 0.25, 2: 0.5, 3: 0.75}


def midi_key_to_freq(wfreq, key, fine):
    """Exact m4a MidiKeyToFreq; returns playback rate in Hz."""
    if key > 178:
        key, fine = 178, 255

    def v(k):
        s = SCALE[k]
        return FREQ_TABLE[s & 15] >> (s >> 4)
    v1, v2 = v(key), v(key + 1)
    val = v1 + (((v2 - v1) * (fine << 24)) >> 32)
    return float((wfreq * val) >> 32)


def midi_key_to_cgb(ch, key, fine):
    """Returns tone frequency in Hz (square: duty cycle freq, wave: 32-sample cycle freq,
    noise: LFSR clock)."""
    if ch == 4:
        k = 0 if key <= 20 else min(key - 21, 59)
        r = NOISE_TABLE[k]
        s, div = r >> 4, r & 7
        return 524288.0 / (div if div else 0.5) / (2 ** (s + 1))
    if key <= 35:
        fine, key = 0, 0
    else:
        key -= 36
        if key > 130:
            key, fine = 130, 255

    def v(k):
        s = k // 12 * 16 + k % 12
        return CGB_FREQ[s & 15] >> (s >> 4)
    v1, v2 = v(key), v(key + 1)
    reg = v1 + ((fine * (v2 - v1)) >> 8) + 2048
    reg &= 0x7FF
    period = 2048 - reg
    if period <= 0:
        period = 1
    if ch == 3:
        return 65536.0 / period
    return 131072.0 / period


def _lfsr(width7):
    lf = 0x7FFF if not width7 else 0x7F
    out = []
    period = 127 if width7 else 32767
    for _ in range(period):
        x = (lf ^ (lf >> 1)) & 1
        lf = (lf >> 1) | (x << (6 if width7 else 14))
        out.append(0.5 if (lf & 1) == 0 else -0.5)
    return np.array(out, np.float32)


LFSR15 = _lfsr(False)
LFSR7 = _lfsr(True)


SOLO = None
if os.environ.get('M4A_SOLO'):
    SOLO = set(int(x) for x in os.environ['M4A_SOLO'].split(','))


def s8(x):
    x &= 0xFF
    return x - 256 if x & 0x80 else x


class Track:
    def __init__(self, idx, ptr):
        self.idx = idx
        self.ptr = ptr
        self.exist = True
        self.start = True
        self.reset()

    def reset(self):
        self.wait = 0
        self.running = 0
        self.patt = []
        self.rep_n = 0
        self.key = 0
        self.velocity = 0
        self.gate = 0
        self.vol = 0
        self.volX = 64
        self.pan = 0
        self.panX = 0
        self.bend = 0
        self.bendRange = 2
        self.tune = 0
        self.keyShift = 0
        self.keyShiftX = 0
        self.pitX = 0
        self.lfoSpeed = 22
        self.lfoSpeedC = 0
        self.lfoDelay = 0
        self.lfoDelayC = 0
        self.mod = 0
        self.modT = 0
        self.modM = 0
        self.priority = 0
        self.echoVol = 0
        self.echoLen = 0
        self.tone = None
        self.volset = True
        self.pitset = True
        self.volMR = self.volML = 0
        self.keyM = 0
        self.pitM = 0
        self.chans = []

    def vol_pit_set(self):
        if self.volset:
            x = (self.vol * self.volX) >> 5
            if self.modT == 1:
                x = (x * (self.modM + 128)) >> 7
            y = 2 * self.pan + self.panX
            if self.modT == 2:
                y += self.modM
            y = max(-128, min(127, y))
            self.volMR = (((y + 128) * x) >> 8) & 0xFF
            self.volML = (((127 - y) * x) >> 8) & 0xFF
        if self.pitset:
            bend = self.bend * self.bendRange
            x = (self.tune + bend) * 4 + (self.keyShift << 8) + (self.keyShiftX << 8) + self.pitX
            if self.modT == 0:
                x += 16 * self.modM
            self.keyM = s8(x >> 8) if -128 <= (x >> 8) <= 127 else (x >> 8)
            self.pitM = x & 0xFF
        self.volset = self.pitset = False


# channel status
ENV_RELEASE, ENV_SUSTAIN, ENV_DECAY, ENV_ATTACK = 0, 1, 2, 3


class Chan:
    def __init__(self, cgb=0):
        self.cgb = cgb
        self.on = False
        self.start = False
        self.stop = False
        self.env_state = 0
        self.track = None
        self.prio = 0
        self.alloc_seq = 0

    def vol_set(self):
        t = self.track
        r = ((self.rhythmPan + 128) * self.velocity * t.volMR) >> 14
        l = ((127 - self.rhythmPan) * self.velocity * t.volML) >> 14
        self.rightVolume = min(r, 255)
        self.leftVolume = min(l, 255)

    def pitch_set(self):
        t = self.track
        key = self.key + t.keyM
        if key < 0:
            key = 0
        if self.cgb:
            self.freq = midi_key_to_cgb(self.cgb, key, t.pitM)
        else:
            self.freq = midi_key_to_freq(self.wav.freq, key, t.pitM)


class Player:
    def __init__(self, num, loops=2, tail=1.0):
        self.song = Song(num)
        self.bank = VoiceBank()
        self.group = self.bank.asm.labels[self.song.group]
        self.tracks = [Track(i, p) for i, p in enumerate(self.song.tracks)]
        self.pcm = [Chan() for _ in range(MAX_PCM)]
        self.cgbch = [Chan(c) for c in (1, 2, 3, 4)]
        self.tempoD = 150
        self.tempoI = 150
        self.tempoC = 0
        self.frame = 0
        self.tick = 0
        self.alloc_counter = 0
        self.visit = {}            # track-0 command offset -> first frame
        self.goto_frames = []
        self.loop_start_frame = None
        self.loops = loops
        self.tail = tail
        self.finished = False
        self.c15 = 0
        rev = self.song.reverb
        self.reverb = (rev & 0x7F) if rev & 0x80 else 0

    # -------------------------------------------------------------- sequencer
    def rd(self, t):
        b = self.song.data[t.ptr]
        t.ptr += 1
        return b

    def rd_word(self, t):
        d = self.song.data
        v = int.from_bytes(d[t.ptr:t.ptr + 4], 'little')
        return v

    def do_tick(self):
        for t in self.tracks:
            if not t.exist:
                continue
            # gate countdown
            for c in t.chans:
                if c.on and c.gate:
                    c.gate -= 1
                    if c.gate == 0:
                        c.stop = True
            t.chans = [c for c in t.chans if c.on and c.track is t]
            if t.start:
                ptr = t.ptr
                t.reset()
                t.ptr = ptr
                t.start = False
                t.volset = t.pitset = False
            while t.wait == 0 and t.exist:
                if t.idx == 0 and t.ptr not in self.visit:
                    self.visit[t.ptr] = self.frame
                self.command(t)
            if not t.exist:
                continue
            t.wait -= 1
            # LFO
            if t.lfoSpeed and t.mod:
                if t.lfoDelayC:
                    t.lfoDelayC -= 1
                else:
                    t.lfoSpeedC = (t.lfoSpeedC + t.lfoSpeed) & 0xFF
                    if s8(t.lfoSpeedC - 64) < 0:
                        r = s8(t.lfoSpeedC)
                    else:
                        r = 128 - t.lfoSpeedC
                    r = (t.mod * r) >> 6
                    if s8(r) != t.modM:
                        t.modM = s8(r)
                        if t.modT == 0:
                            t.pitset = True
                        else:
                            t.volset = True
        self.tick += 1

    def command(self, t):
        d = self.song.data
        cmd = d[t.ptr]
        if cmd < 0x80:
            cmd = t.running
        else:
            t.ptr += 1
            if cmd >= 0xBD:
                t.running = cmd
        if cmd >= 0xCF:
            self.note(t, cmd - 0xCF)
        elif cmd > 0xB0:
            self.ctrl(t, cmd)
        else:
            t.wait = CLOCK[cmd - 0x80]

    def ctrl(self, t, cmd):
        if cmd == 0xB1 or cmd in (0xB6, 0xB7, 0xB8, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCC):  # FINE
            self.track_stop(t)
            t.exist = False
        elif cmd == 0xB2:   # GOTO
            target = self.rd_word(t)
            if t.idx == 0:
                self.goto_frames.append(self.frame)
                if self.loop_start_frame is None:
                    self.loop_start_frame = self.visit.get(target)
                    self.loop_target = target
            t.ptr = target
        elif cmd == 0xB3:   # PATT
            if len(t.patt) < 3:
                t.patt.append(t.ptr + 4)
                t.ptr = self.rd_word(t)
            else:
                self.track_stop(t)
                t.exist = False
        elif cmd == 0xB4:   # PEND
            if t.patt:
                t.ptr = t.patt.pop()
        elif cmd == 0xB5:   # REPT
            n = d = self.song.data[t.ptr]
            if n == 0:
                t.ptr += 1
                t.ptr = self.rd_word(t)
            else:
                t.rep_n += 1
                if t.rep_n < n:
                    t.ptr += 1
                    t.ptr = self.rd_word(t)
                else:
                    t.rep_n = 0
                    t.ptr += 5
        elif cmd == 0xB9:   # MEMACC: op, addr, data (+ word for branches) -- not used in BGM
            op = self.rd(t)
            self.rd(t)
            self.rd(t)
            if op >= 6:
                t.ptr += 4
        elif cmd == 0xBA:
            t.priority = self.rd(t)
        elif cmd == 0xBB:
            self.tempoD = self.rd(t) * 2
            self.tempoI = self.tempoD
        elif cmd == 0xBC:
            t.keyShift = s8(self.rd(t))
            t.volset = t.pitset = True
        elif cmd == 0xBD:
            v = self.rd(t)
            t.tone = self.bank.tone(self.group, v)
        elif cmd == 0xBE:
            t.vol = self.rd(t)
            t.volset = True
        elif cmd == 0xBF:
            t.pan = s8(self.rd(t) - 0x40)
            t.volset = True
        elif cmd == 0xC0:
            t.bend = s8(self.rd(t) - 0x40)
            t.pitset = True
        elif cmd == 0xC1:
            t.bendRange = self.rd(t)
            t.pitset = True
        elif cmd == 0xC2:
            t.lfoSpeed = self.rd(t)
            if t.lfoSpeed == 0:
                self.clear_modM(t)
        elif cmd == 0xC3:
            t.lfoDelay = self.rd(t)
        elif cmd == 0xC4:
            t.mod = self.rd(t)
            if t.mod == 0:
                self.clear_modM(t)
        elif cmd == 0xC5:
            v = self.rd(t)
            if v != t.modT:
                t.modT = v
                t.volset = t.pitset = True
        elif cmd == 0xC8:
            t.tune = s8(self.rd(t) - 0x40)
            t.pitset = True
        elif cmd == 0xCD:   # XCMD
            x = self.rd(t)
            v = self.rd(t)
            if x == 0x08:
                t.echoVol = v
            elif x == 0x09:
                t.echoLen = v
        elif cmd == 0xCE:   # EOT
            if self.song.data[t.ptr] < 0x80:
                t.key = self.rd(t)
            for c in t.chans:
                if c.on and (c.start or c.env_state) and not c.stop and c.midiKey == t.key:
                    c.stop = True
                    break
        else:
            raise ValueError('unhandled cmd %02X' % cmd)

    def clear_modM(self, t):
        t.modM = 0
        t.lfoSpeedC = 0
        if t.modT == 0:
            t.pitset = True
        else:
            t.volset = True

    def track_stop(self, t):
        for c in t.chans:
            if c.on:
                c.on = False
            c.track = None
        t.chans = []

    def note(self, t, idx):
        d = self.song.data
        t.gate = CLOCK[idx]
        if d[t.ptr] < 0x80:
            t.key = d[t.ptr]
            t.ptr += 1
            if d[t.ptr] < 0x80:
                t.velocity = d[t.ptr]
                t.ptr += 1
                if d[t.ptr] < 0x80:
                    t.gate += d[t.ptr]
                    t.ptr += 1
        tone = t.tone
        if tone is None:
            return
        rhythm_pan = 0
        key = t.key
        if tone.type & 0xC0:
            k = t.key
            if tone.type & 0x40:
                k = self.bank.keymap(tone.keymap, k)
            sub = self.bank.tone_at(tone.sub + 12 * k)
            if sub.type & 0xC0:
                return
            if tone.type & 0x80:
                if sub.pan_sweep & 0x80:
                    rhythm_pan = (sub.pan_sweep - 0xC0) * 2
                key = sub.key
            tone = sub
        prio = min(255, self.song.priority + t.priority)
        cgb = tone.type & 7
        if cgb:
            c = self.cgbch[cgb - 1]
            if c.on and not c.stop:
                if c.prio > prio:
                    return
                if c.prio == prio and c.track is not None and c.track.idx < t.idx:
                    return
        else:
            c = None
            found_rel = False
            best_p = prio
            best_t = t.idx
            for ch in self.pcm:
                if not ch.on:
                    c = ch
                    break
                ctidx = ch.track.idx if ch.track is not None else 99
                if ch.stop:
                    if not found_rel:
                        found_rel = True
                        best_p, best_t, c = ch.prio, ctidx, ch
                        continue
                elif found_rel:
                    continue
                if ch.prio < best_p:
                    best_p, best_t, c = ch.prio, ctidx, ch
                elif ch.prio > best_p:
                    continue
                elif ctidx >= best_t:
                    best_t, c = ctidx, ch
            if c is None:
                return
        # ClearChain
        if c.track is not None and c in c.track.chans:
            c.track.chans.remove(c)
        t.chans.insert(0, c)
        c.track = t
        t.lfoDelayC = t.lfoDelay
        if t.lfoDelay:
            self.clear_modM(t)
        t.vol_pit_set()
        c.gate = t.gate
        c.prio = prio
        c.key = key
        c.midiKey = t.key
        c.velocity = t.velocity
        c.rhythmPan = rhythm_pan
        c.type = tone.type
        c.wav = tone.wav
        c.attack, c.decay, c.sustain, c.release = tone.attack, tone.decay, tone.sustain, tone.release
        c.echoVol = t.echoVol
        c.echoLen = t.echoLen
        c.vol_set()
        c.pitch_set()
        if SOLO is not None and t.idx not in SOLO:
            c.velocity = 0
            c.vol_set()
        c.on = True
        c.start = True
        c.stop = False
        c.env_state = 0
        c.iec = False

    # -------------------------------------------------------------- envelopes
    def pcm_envelope(self, c):
        """SoundMainRAM per-frame envelope. Returns False when channel stops."""
        if c.start:
            if c.stop:
                c.on = False
                return False
            c.start = False
            c.env_state = ENV_ATTACK
            c.pos = 0.0
            c.env = 0
            c.loop = c.wav.loop
            env = c.env + c.attack
            if env >= 0xFF:
                env = 0xFF
                c.env_state = ENV_DECAY
            c.env = env
            return True
        env = c.env
        if c.iec:
            c.echoLen -= 1
            if c.echoLen <= 0:
                c.on = False
                return False
            return True
        if c.stop:
            env = (env * c.release) >> 8
            if env <= c.echoVol:
                env = c.echoVol
                if env == 0:
                    c.on = False
                    return False
                c.iec = True
            c.env = env
            return True
        if c.env_state == ENV_DECAY:
            env = (env * c.decay) >> 8
            if env <= c.sustain:
                env = c.sustain
                if env == 0:
                    env = c.echoVol
                    if env == 0:
                        c.on = False
                        return False
                    c.iec = True
                else:
                    c.env_state = ENV_SUSTAIN
        elif c.env_state == ENV_ATTACK:
            env += c.attack
            if env >= 0xFF:
                env = 0xFF
                c.env_state = ENV_DECAY
        c.env = env
        return True

    def cgb_modvol(self, c):
        r, l = c.rightVolume, c.leftVolume
        panned = False
        if r >= l:
            if r // 2 >= l:
                c.pan = (1, 0)
                panned = True
        else:
            if l // 2 >= r:
                c.pan = (0, 1)
                panned = True
        if not panned:
            c.pan = (1, 1)
        c.goal = (r + l) // 16
        if panned and c.goal > 15:
            c.goal = 15
        c.goal = min(c.goal, 15)
        c.sus_goal = (c.goal * c.sustain + 15) >> 4

    def cgb_envelope(self):
        if self.c15:
            self.c15 -= 1
        else:
            self.c15 = 14
        for c in self.cgbch:
            if not c.on:
                continue
            prev = self.c15
            state = None
            if c.start:
                if c.stop:
                    c.on = False
                    continue
                c.start = False
                c.env_state = ENV_ATTACK
                c.phase = 0.0
                c.lfsr = 0
                self.cgb_modvol(c)
                c.counter = c.attack
                if c.attack:
                    c.env = 0
                    state = 'complete'
                else:
                    state = 'decay_start'
            elif c.iec:
                c.echoLen -= 1
                if c.echoLen <= 0:
                    c.on = False
                continue
            elif c.stop and c.env_state != ENV_RELEASE:
                c.env_state = ENV_RELEASE
                c.counter = c.release
                if c.release:
                    state = 'complete'
                else:
                    state = 'echo'
            else:
                state = 'repeat'
            while True:
                if state == 'repeat':
                    state = 'complete'
                    if c.counter == 0:
                        self.cgb_modvol(c)
                        if c.env_state == ENV_RELEASE:
                            c.env -= 1
                            if c.env <= 0:
                                state = 'echo'
                            else:
                                c.counter = c.release
                        elif c.env_state == ENV_SUSTAIN:
                            c.env = c.sus_goal
                            c.counter = 7
                        elif c.env_state == ENV_DECAY:
                            c.env -= 1
                            if c.env <= c.sus_goal:
                                state = 'sustain_start'
                            else:
                                c.counter = c.decay
                        else:
                            c.env += 1
                            if c.env >= c.goal:
                                state = 'decay_start'
                            else:
                                c.counter = c.attack
                if state == 'decay_start':
                    c.env_state = ENV_DECAY
                    c.counter = c.decay
                    if c.decay:
                        c.env = c.goal
                        state = 'complete'
                    else:
                        state = 'sustain_start'
                if state == 'sustain_start':
                    if c.sustain == 0:
                        c.env_state = ENV_RELEASE
                        state = 'echo'
                    else:
                        c.env_state = ENV_SUSTAIN
                        c.env = c.sus_goal
                        c.counter = 7
                        state = 'complete'
                if state == 'echo':
                    c.env = (c.goal * c.echoVol + 0xFF) >> 8
                    if c.env:
                        c.iec = True
                    else:
                        c.on = False
                    break
                if state == 'complete':
                    c.counter = (c.counter - 1) & 0xFF
                    if prev == 0:
                        prev = -1
                        state = 'repeat'
                        continue
                    break

    # -------------------------------------------------------------- mixing
    def render_pcm(self, c, n, outL, outR):
        w = c.wav
        fixed = bool(c.type & 0x08)
        step = (MIX_RATE if fixed else c.freq) / OUT_RATE
        pos = c.pos + step * np.arange(n, dtype=np.float64)
        size = w.size
        if c.loop and size > w.loop_start:
            ls = w.loop_start
            ll = size - ls
            over = pos >= size
            if over.any():
                pos = np.where(over, ls + np.mod(pos - ls, ll), pos)
            valid = n
        else:
            valid = int(np.searchsorted(pos, size))
            pos = pos[:valid]
        if valid > 0:
            i = pos.astype(np.int64)
            f = (pos - i).astype(np.float32)
            a = w.pcm[i]
            b = w.pcm[np.minimum(i + 1, size)]
            smp = a + (b - a) * f if INTERP else a
            env = (c.env * (MASTER_VOL + 1)) >> 4
            vr = (c.rightVolume * env) >> 8
            vl = (c.leftVolume * env) >> 8
            outR[:valid] += smp * (vr / 256.0 / 128.0)
            outL[:valid] += smp * (vl / 256.0 / 128.0)
        newpos = c.pos + step * n
        if c.loop and size > w.loop_start and newpos >= size:
            newpos = w.loop_start + math.fmod(newpos - w.loop_start, size - w.loop_start)
        c.pos = newpos
        if not c.loop and c.pos >= size:
            c.on = False

    def render_cgb(self, c, n, outL, outR):
        if c.env <= 0:
            return
        f = c.freq
        if c.cgb in (1, 2):
            duty = DUTY.get(c.wav & 3, 0.5)
            ph = c.phase + f / OUT_RATE * np.arange(1, n + 1)
            frac = np.mod(ph, 1.0)
            sig = np.where(frac < duty, 1.0 - duty, -duty).astype(np.float32)
            c.phase = float(ph[-1] % 1.0)
            amp = c.env / 15.0
        elif c.cgb == 3:
            ph = c.phase + f / OUT_RATE * np.arange(1, n + 1)
            idx = (np.mod(ph, 1.0) * 32).astype(np.int64) % 32
            s = c.wav.samples
            sig = ((s - s.mean()) / 15.0)[idx].astype(np.float32)
            c.phase = float(ph[-1] % 1.0)
            amp = CGB3_VOL[min(c.env, 15)] * WAVE_GAIN
        else:
            # LFSR noise clocked at f Hz (precomputed periodic LFSR output)
            seq = LFSR7 if (c.wav & 1) else LFSR15
            clocks = c.phase + f / OUT_RATE * np.arange(1, n + 1)
            idx = (clocks.astype(np.int64) + c.lfsr) % len(seq)
            sig = seq[idx]
            whole = int(clocks[-1])
            c.lfsr = (c.lfsr + whole) % len(seq)
            c.phase = float(clocks[-1] - whole)
            amp = c.env / 15.0
        a = amp * CGB_AMP
        if c.pan[1]:
            outL += sig * a
        if c.pan[0]:
            outR += sig * a

    # -------------------------------------------------------------- main loop
    def run(self):
        spf = OUT_RATE / FRAME_RATE
        chunksL, chunksR, cgbL, cgbR = [], [], [], []
        acc = 0.0
        end_frame = None
        while True:
            # sequencer
            if not self.finished:
                self.tempoC += self.tempoI
                while self.tempoC >= 150:
                    self.do_tick()
                    self.tempoC -= 150
                    if len(self.goto_frames) >= self.loops and end_frame is None:
                        end_frame = self.frame + int(round(self.tail * FRAME_RATE))
                    if not any(t.exist for t in self.tracks):
                        self.finished = True
                        if end_frame is None:
                            end_frame = self.frame + int(round(3 * FRAME_RATE))
                        break
                for t in self.tracks:
                    if t.exist and (t.volset or t.pitset):
                        vs, ps = t.volset, t.pitset
                        t.vol_pit_set()
                        for c in t.chans:
                            if not c.on:
                                continue
                            if vs:
                                c.vol_set()
                            if ps:
                                c.pitch_set()
            self.cgb_envelope()
            acc += spf
            n = int(acc)
            acc -= n
            L = np.zeros(n, np.float32)
            R = np.zeros(n, np.float32)
            CL = np.zeros(n, np.float32)
            CR = np.zeros(n, np.float32)
            for c in self.pcm:
                if c.on:
                    if self.pcm_envelope(c):
                        self.render_pcm(c, n, L, R)
            for c in self.cgbch:
                if c.on:
                    self.render_cgb(c, n, CL, CR)
            chunksL.append(L)
            chunksR.append(R)
            cgbL.append(CL)
            cgbR.append(CR)
            self.frame += 1
            if end_frame is not None and self.frame >= end_frame:
                break
            if self.frame > FRAME_RATE * 900:
                break
        L = np.concatenate(chunksL)
        R = np.concatenate(chunksR)
        if ZOH:
            # the m4a mixer outputs the DirectSound mix at 18157 Hz (sample-and-hold)
            k = np.floor(np.floor(np.arange(len(L)) * (MIX_RATE / OUT_RATE)) * (OUT_RATE / MIX_RATE) + 0.5).astype(np.int64)
            k = np.minimum(k, len(L) - 1)
            L, R = L[k], R[k]
        if self.reverb:     # m4a reverb works on the DirectSound buffer only
            L, R = apply_reverb(L, R, self.reverb)
        L = L + np.concatenate(cgbL)
        R = R + np.concatenate(cgbR)
        if WIDTH != 1.0:
            M, S = (L + R) / 2, (L - R) / 2 * WIDTH
            L, R = M + S, M - S
        return L, R


def apply_reverb(L, R, rev):
    """m4a reverb: buffer slot is pre-filled with (L+R)[n-5 frames] + (L+R)[n-4 frames]
    (the DMA ring holds 5 frames) times rev/512, i.e. a feedback comb on the final mix."""
    d5 = int(round(5 * OUT_RATE / FRAME_RATE))
    d4 = int(round(4 * OUT_RATE / FRAME_RATE))
    g = rev / 512.0
    n = len(L)
    yL = L.astype(np.float64).copy()
    yR = R.astype(np.float64).copy()
    pos = d4
    while pos < n:
        e = min(n, pos + d4)
        a = pos - d5
        fb = np.zeros(e - pos)
        s5 = slice(max(a, 0), e - d5) if e - d5 > 0 else None
        if s5 is not None and e - d5 > max(a, 0):
            src = yL[max(a, 0):e - d5] + yR[max(a, 0):e - d5]
            fb[(max(a, 0) - a):(max(a, 0) - a) + len(src)] += src
        src4 = yL[pos - d4:e - d4] + yR[pos - d4:e - d4]
        fb[:len(src4)] += src4
        yL[pos:e] += fb * g
        yR[pos:e] += fb * g
        pos = e
    return yL.astype(np.float32), yR.astype(np.float32)


def write_wav(path, L, R, gain=1.0):
    import wave
    st = np.stack([L, R], axis=1) * gain
    pcm = np.clip(st * 32767.0, -32768, 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(OUT_RATE)
        w.writeframes(pcm.tobytes())


def main():
    args = sys.argv[1:]
    tail = 1.0
    gain = None
    if '--tail' in args:
        i = args.index('--tail')
        tail = float(args[i + 1])
        del args[i:i + 2]
    if '--gain' in args:
        i = args.index('--gain')
        gain = float(args[i + 1])
        del args[i:i + 2]
    loops = 2
    if '--loops' in args:
        i = args.index('--loops')
        loops = int(args[i + 1])
        del args[i:i + 2]
    num = int(args[0])
    out = args[1]
    p = Player(num, loops=loops, tail=tail)
    L, R = p.run()
    if gain is None:
        # normalise: target RMS of about -16 dBFS (close to the shipped rips)
        rms = float(np.sqrt(np.mean((L.astype(np.float64) ** 2 + R.astype(np.float64) ** 2) / 2)))
        gain = (10 ** (-16 / 20.0)) / rms if rms > 0 else 1.0
        peak = float(max(np.abs(L).max(), np.abs(R).max())) * gain
        if peak > 0.99:
            gain *= 0.99 / peak
    write_wav(out, L, R, gain)
    ls = p.loop_start_frame / FRAME_RATE if p.loop_start_frame is not None else None
    le = p.goto_frames[0] / FRAME_RATE if p.goto_frames else None
    print(json.dumps({'song': num, 'loopStart': round(ls, 4) if ls is not None else None,
                      'loopEnd': round(le, 4) if le is not None else None,
                      'duration': round(len(L) / OUT_RATE, 4), 'gain': gain,
                      'frames': p.frame}))


if __name__ == '__main__':
    main()
