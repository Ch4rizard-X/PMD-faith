"""Render PMD:EoS DSE BGM (SMDL + SWDL) to audio, modelled on the arm9 DSE driver.

Engine facts used (reverse engineered from arm9.bin of C2SE, see notes in report):
 * tick = 60 / (tempo * tpqn) s; tpqn = 48.
 * pitch (1/256 semitone) P = (key + split.ktps + split.ctune)*256 + split.ftune(u8)
   + track tune (D0-D4) + bend*range*256/8192 ; rate = 32728 * 2^((P/256 - 60)/12)
 * volume: v = env/127 * (vel*prgvol*splitvol/127^2)/127 * (trkvol*expr/127^2) ; amp = v^2
 * pan = splitpan + trkpan - 64 (0..127), linear L=(128-p)/128, R=p/128
 * envelope: DSE AHDSR state machine stepped at 100 Hz, durations in ms (table*envmult)
 * note off at tick + dur (min 1 tick); new note on same key releases the held one
 * 0x98 without loop point hard-cuts the track's voices.
"""
import math
import struct
import numpy as np
from dse import SMD, SWD, FIXED_RESTS, ARGLEN, parse_track_events

D16 = [0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000A, 0x000B, 0x000C,
       0x000D, 0x000E, 0x000F, 0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016, 0x0017, 0x0018, 0x0019,
       0x001A, 0x001B, 0x001C, 0x001D, 0x001E, 0x001F, 0x0020, 0x0023, 0x0028, 0x002D, 0x0033, 0x0039, 0x0040,
       0x0048, 0x0050, 0x0058, 0x0062, 0x006D, 0x0078, 0x0083, 0x0090, 0x009E, 0x00AC, 0x00BC, 0x00CC, 0x00DE,
       0x00F0, 0x0104, 0x0119, 0x012F, 0x0147, 0x0160, 0x017A, 0x0196, 0x01B3, 0x01D2, 0x01F2, 0x0214, 0x0238,
       0x025E, 0x0285, 0x02AE, 0x02D9, 0x0307, 0x0336, 0x0367, 0x039B, 0x03D1, 0x0406, 0x0442, 0x047E, 0x04C4,
       0x0500, 0x0546, 0x058C, 0x0622, 0x0672, 0x06CC, 0x071C, 0x0776, 0x07DA, 0x0834, 0x0898, 0x0906, 0x096A,
       0x09D8, 0x0A50, 0x0ABE, 0x0B40, 0x0BB8, 0x0C3A, 0x0CBC, 0x0D48, 0x0DDE, 0x0E6A, 0x0F00, 0x0FA0, 0x1040,
       0x10EA, 0x1194, 0x123E, 0x12F2, 0x13B0, 0x146E, 0x1536, 0x15FE, 0x16D0, 0x17A2, 0x187E, 0x195A, 0x1A40,
       0x1B30, 0x1C20, 0x1D1A, 0x1E1E, 0x1F22, 0x2030, 0x2148, 0x2260, 0x2382, 0x2710, 0x7FFF]
D32 = [0x00000000, 0x00000004, 0x00000007, 0x0000000A, 0x0000000F, 0x00000015, 0x0000001C, 0x00000024,
       0x0000002E, 0x0000003A, 0x00000048, 0x00000057, 0x00000068, 0x0000007B, 0x00000091, 0x000000A8,
       0x00000185, 0x000001BE, 0x000001FC, 0x0000023F, 0x00000288, 0x000002D6, 0x0000032A, 0x00000385,
       0x000003E5, 0x0000044C, 0x000004BA, 0x0000052E, 0x000005A9, 0x0000062C, 0x000006B5, 0x00000746,
       0x00000BCF, 0x00000CC0, 0x00000DBD, 0x00000EC6, 0x00000FDC, 0x000010FF, 0x0000122F, 0x0000136C,
       0x000014B6, 0x0000160F, 0x00001775, 0x000018EA, 0x00001A6D, 0x00001BFF, 0x00001DA0, 0x00001F51,
       0x00002C16, 0x00002E80, 0x00003100, 0x00003395, 0x00003641, 0x00003902, 0x00003BDB, 0x00003ECA,
       0x000041D0, 0x000044EE, 0x00004824, 0x00004B73, 0x00004ED9, 0x00005259, 0x000055F2, 0x000059A4,
       0x000074CC, 0x000079AB, 0x00007EAC, 0x000083CE, 0x00008911, 0x00008E77, 0x000093FF, 0x000099AA,
       0x00009F78, 0x0000A56A, 0x0000AB80, 0x0000B1BB, 0x0000B81A, 0x0000BE9E, 0x0000C547, 0x0000CC17,
       0x0000FD42, 0x000105CB, 0x00010E82, 0x00011768, 0x0001207E, 0x000129C4, 0x0001333B, 0x00013CE2,
       0x000146BB, 0x000150C5, 0x00015B02, 0x00016572, 0x00017015, 0x00017AEB, 0x000185F5, 0x00019133,
       0x0001E16D, 0x0001EF07, 0x0001FCE0, 0x00020AF7, 0x0002194F, 0x000227E6, 0x000236BE, 0x000245D7,
       0x00025532, 0x000264CF, 0x000274AE, 0x000284D0, 0x00029536, 0x0002A5E0, 0x0002B6CE, 0x0002C802,
       0x000341B0, 0x000355F8, 0x00036A90, 0x00037F79, 0x000394B4, 0x0003AA41, 0x0003C021, 0x0003D654,
       0x0003ECDA, 0x000403B5, 0x00041AE5, 0x0004326A, 0x00044A45, 0x00046277, 0x00047B00, 0x7FFFFFFF]

CTL_DEFAULTS = {'vol': 100, 'expr': 127, 'pan': 64, 'bend': 0, 'tune': 0, 'bendrange': 0, 'mod': 0}
FRAME = 0.01        # DSE driver update period (10000 us)
INF = 10 ** 9


def s8(b):
    return b - 256 if b > 127 else b


# ----------------------------------------------------------------------------------------------
# Sequencer
# ----------------------------------------------------------------------------------------------
class Note:
    __slots__ = ('trk', 'tick', 'key', 'vel', 'off', 'prog', 'legato', 'envov', 'keys', 'kill', 'order')


class TrackOut:
    def __init__(self):
        self.notes = []
        self.ctl = {k: [] for k in CTL_DEFAULTS}
        self.kill_tick = None
        self.loop_tick = None
        self.end_tick = None


def simulate_track(d, t, tick_limit, tempo_out, trk_index, loop_enabled=True):
    """Run one track up to tick_limit, return TrackOut. Tempo events appended to tempo_out."""
    evs = parse_track_events(d, t)
    pos_of = {o: i for i, (o, c, a) in enumerate(evs)}
    out = TrackOut()
    i = 0
    tick = 0
    octave = 4
    last_rest = 0
    last_dur = 0
    loop_i = None
    prog = 0
    vol, expr, pan = 100, 127, 64
    tune = 0
    bend = 0
    sweep_cur = 0.0
    sweep_inc = 0.0
    sweep_cnt = 0
    sweep_tgt = 0
    vol_cur = 100.0
    vol_inc = 0.0
    vol_cnt = 0
    vol_tgt = 100
    pan_cur = 64.0
    pan_inc = 0.0
    pan_cnt = 0
    pan_tgt = 64
    legato_flag = False
    last_key = None
    envov = [255] * 7   # atkvol, attack, decay, sustain, hold, decay2, release
    rep_stack = []
    held = {}           # key -> Note (key-down notes)
    order = 0

    def setc(name, val):
        lst = out.ctl[name]
        if lst and lst[-1][0] == tick:
            lst[-1] = (tick, val)
        else:
            lst.append((tick, val))

    nev = len(evs)
    guard = 0
    while tick < tick_limit:
        # --- per-tick sweeps (applied before this tick's events) ---
        # process events until a wait is produced
        wait = 0
        while i < nev and wait == 0:
            guard += 1
            if guard > 2000000:
                raise RuntimeError('runaway track')
            o, c, a = evs[i]
            i += 1
            if a is None:
                # unknown opcode -> stop track
                i = nev
                break
            if c < 0x80:
                arg = a[0]
                octave = (octave + ((arg >> 4) & 3) - 2) & 0xFF
                key = octave * 12 + (arg & 0xF)
                n = (arg >> 6) & 3
                if n:
                    dur = int.from_bytes(a[1:1 + n], 'big')
                    last_dur = dur
                else:
                    dur = last_dur
                off = tick + max(dur, 1)
                if legato_flag and last_key is not None and last_key in held:
                    nt = held.pop(last_key)
                    nt.off = off
                    nt.keys.append((tick, key))
                    held[key] = nt
                    legato_flag = False
                    last_key = key
                    sweep_cur = sweep_cur  # no reset on legato
                    continue
                legato_flag = False
                # same key held -> release it now
                if key in held:
                    p = held.pop(key)
                    if p.off > tick:
                        p.off = tick
                sweep_cur = 0.0
                setc('tune', tune + int(sweep_cur))
                nt = Note()
                nt.trk = trk_index
                nt.tick = tick
                nt.key = key
                nt.vel = c
                nt.off = off
                nt.prog = prog
                nt.legato = False
                nt.envov = tuple(envov)
                nt.keys = [(tick, key)]
                nt.kill = None
                nt.order = order
                order += 1
                out.notes.append(nt)
                held[key] = nt
                last_key = key
                continue
            if c < 0x90:
                last_rest = FIXED_RESTS[c - 0x80]
                wait = last_rest
                continue
            if c == 0x90:
                wait = last_rest
            elif c == 0x91:
                last_rest = max(0, last_rest + s8(a[0]))
                wait = last_rest
            elif c == 0x92:
                last_rest = a[0]
                wait = last_rest
            elif c == 0x93:
                last_rest = a[0] | a[1] << 8
                wait = last_rest
            elif c == 0x94:
                last_rest = a[0] | a[1] << 8 | a[2] << 16
                wait = last_rest
            elif c == 0x95:
                wait = max(1, a[0])  # approximation: single wait
            elif c == 0x98:
                if out.end_tick is None:
                    out.end_tick = tick
                if loop_i is not None and loop_enabled:
                    i = loop_i
                else:
                    out.kill_tick = tick
                    i = nev
                    break
            elif c == 0x99:
                loop_i = i
                if out.loop_tick is None:
                    out.loop_tick = tick
            elif c == 0x9C:
                rep_stack.append([i, a[0], octave, None])
            elif c == 0x9D:
                if rep_stack:
                    fr = rep_stack[-1]
                    fr[1] -= 1
                    if fr[1] <= 0:
                        rep_stack.pop()
                    else:
                        fr[3] = i
                        i = fr[0]
                        octave = fr[2]
            elif c == 0x9E:
                if rep_stack:
                    fr = rep_stack[-1]
                    if fr[1] - 1 <= 0 and fr[3] is not None:
                        i = fr[3]
                        rep_stack.pop()
            elif c == 0xA0:
                octave = a[0]
            elif c == 0xA1:
                octave = (octave + s8(a[0])) & 0xFF
            elif c in (0xA4, 0xA5):
                tempo_out.append((tick, a[0], trk_index))
            elif c == 0xAC:
                prog = a[0]
            elif c == 0xB0:
                envov = [255] * 7
            elif c == 0xB1:
                envov[0] = a[0]
            elif c == 0xB2:
                envov[1] = a[0]
            elif c == 0xB3:
                envov[4] = a[0]
            elif c == 0xB4:
                if a[0] != 255:
                    envov[2] = a[0]
                if a[1] != 255:
                    envov[3] = a[1]
            elif c == 0xB5:
                envov[5] = a[0]
            elif c == 0xB6:
                envov[6] = a[0]
            elif c == 0xC0:
                legato_flag = True
            elif c == 0xD0:
                tune = s8(a[0]) * 256
                setc('tune', tune + int(sweep_cur))
            elif c == 0xD1:
                tune += s8(a[0]) * 256
                setc('tune', tune + int(sweep_cur))
            elif c == 0xD2:
                tune += s8(a[0]) * 4
                setc('tune', tune + int(sweep_cur))
            elif c == 0xD3:
                tune += struct.unpack('<h', a)[0]
                setc('tune', tune + int(sweep_cur))
            elif c == 0xD4:
                dur = a[0] | a[1] << 8
                if not legato_flag:
                    sweep_cur = 0.0
                sweep_tgt = sweep_cur + s8(a[2]) * 256
                if dur == 0:
                    sweep_cur = float(sweep_tgt)
                    sweep_cnt = 0
                else:
                    sweep_inc = (sweep_tgt - sweep_cur) / dur
                    sweep_cnt = dur
                setc('tune', tune + int(sweep_cur))
            elif c == 0xD7:
                bend = struct.unpack('>h', a)[0]
                setc('bend', bend)
            elif c == 0xDB:
                setc('bendrange', a[0])
            elif c == 0xBE:
                setc('mod', s8(a[0]))
            elif c == 0xE0:
                vol = min(s8(a[0]), 127)
                vol_cur = float(vol)
                vol_cnt = 0
                setc('vol', vol)
            elif c == 0xE1:
                vol = max(0, min(127, int(vol_cur) + s8(a[0])))
                vol_cur = float(vol)
                vol_cnt = 0
                setc('vol', vol)
            elif c == 0xE2:
                dur = a[0] | a[1] << 8
                vol_tgt = s8(a[2])
                if dur == 0:
                    vol_cur = float(vol_tgt)
                    vol_cnt = 0
                    setc('vol', int(vol_cur))
                else:
                    vol_inc = (vol_tgt - vol_cur) / dur
                    vol_cnt = dur
            elif c == 0xE3:
                expr = a[0] & 0x7F if a[0] < 128 else 127
                setc('expr', expr)
            elif c == 0xE8:
                pan = min(a[0], 127)
                pan_cur = float(pan)
                pan_cnt = 0
                setc('pan', pan)
            elif c == 0xE9:
                pan = max(0, min(127, int(pan_cur) + s8(a[0])))
                pan_cur = float(pan)
                pan_cnt = 0
                setc('pan', pan)
            elif c == 0xEA:
                dur = a[0] | a[1] << 8
                pan_tgt = s8(a[2])
                if dur == 0:
                    pan_cur = float(pan_tgt)
                    pan_cnt = 0
                    setc('pan', int(pan_cur))
                else:
                    pan_inc = (pan_tgt - pan_cur) / dur
                    pan_cnt = dur
            # everything else ignored (LFO, mod, swdl/bank selects, unknowns)
        if i >= nev and wait == 0:
            break
        # advance time tick by tick while sweeps are active, otherwise jump
        if vol_cnt or pan_cnt or sweep_cnt:
            for _ in range(wait):
                tick += 1
                if vol_cnt:
                    vol_cnt -= 1
                    vol_cur = float(vol_tgt) if vol_cnt == 0 else vol_cur + vol_inc
                    setc('vol', int(max(0, min(127, vol_cur))))
                if pan_cnt:
                    pan_cnt -= 1
                    pan_cur = float(pan_tgt) if pan_cnt == 0 else pan_cur + pan_inc
                    setc('pan', int(max(0, min(127, pan_cur))))
                if sweep_cnt:
                    sweep_cnt -= 1
                    sweep_cur = float(sweep_tgt) if sweep_cnt == 0 else sweep_cur + sweep_inc
                    setc('tune', tune + int(sweep_cur))
                if tick >= tick_limit:
                    break
        else:
            tick += wait
    if out.end_tick is None:
        out.end_tick = tick
    return out


class TempoMap:
    def __init__(self, events, tpqn=48):
        ev = sorted(events, key=lambda x: (x[0], x[2]))
        ticks = [0]
        bpms = [120]
        for tk, bpm, _ in ev:
            bpm = max(bpm, 1)
            if tk == ticks[-1]:
                bpms[-1] = bpm
            else:
                ticks.append(tk)
                bpms.append(bpm)
        self.ticks = np.array(ticks, dtype=np.float64)
        self.spt = np.array([60.0 / (b * tpqn) for b in bpms])  # seconds per tick
        times = [0.0]
        for k in range(1, len(ticks)):
            times.append(times[-1] + (ticks[k] - ticks[k - 1]) * self.spt[k - 1])
        self.times = np.array(times)

    def t(self, tick):
        tick = np.asarray(tick, dtype=np.float64)
        k = np.searchsorted(self.ticks, tick, side='right') - 1
        k = np.clip(k, 0, len(self.ticks) - 1)
        return self.times[k] + (tick - self.ticks[k]) * self.spt[k]

    def tick(self, t):
        t = np.asarray(t, dtype=np.float64)
        k = np.searchsorted(self.times, t, side='right') - 1
        k = np.clip(k, 0, len(self.times) - 1)
        return self.ticks[k] + (t - self.times[k]) / self.spt[k]


# ----------------------------------------------------------------------------------------------
# Envelope
# ----------------------------------------------------------------------------------------------
def env_frames(param, mult):
    if mult == 0:
        ms = D32[param]
    else:
        ms = D16[param] * mult
    return (ms * 1000) // 10000


def envelope_breakpoints(p, mult):
    """Key-down envelope as list of (frame, level). Last point holds forever.
    p = (atkvol, attack, decay, sustain, hold, decay2, release)."""
    atkvol, attack, decay, sustain, hold, decay2, release = p
    pts = []
    f = 0

    def ramp(v0, target, param):
        """returns (frames_until_transition, end_level) or None for infinite hold."""
        if param == 0x7F:
            return None
        T = env_frames(param, mult)
        return T, target

    # state machine mirroring arm9 0x74e0c / 0x74f54
    if attack != 0:
        v = float(atkvol)
        state = 3
        cur = ramp(v, 127, attack)
    else:
        v = 127.0
        if hold != 0:
            state = 4
            cur = ramp(v, 127, hold)
        elif decay != 0:
            state = 5
            cur = ramp(v, sustain, decay)
        else:
            state = 6
            cur = ramp(v, 0, decay2)
    pts.append((0, v))
    for _ in range(8):
        if cur is None:
            break  # infinite hold at v
        T, target = cur
        # T frames of increments, then at frame T+1 level = target and transition
        if T > 0:
            pts.append((f + T, target))
        f = f + T + 1
        v = float(target)
        pts.append((f, v))
        if state == 3:
            if hold != 0:
                state, cur = 4, ramp(v, 127, hold)
                continue
            state = 4  # fallthrough
        if state == 4:
            if decay != 0:
                state, cur = 5, ramp(v, sustain, decay)
                continue
            v = float(sustain)
            pts.append((f, v))
            state = 5
        if state == 5:
            if decay2 != 0:
                state, cur = 6, ramp(v, 0, decay2)
                continue
            cur = None  # frozen at v
            break
        if state == 6:
            cur = None  # frozen (decay2 done -> level 0)
            break
    # dedupe
    out = []
    for fr, lv in pts:
        if out and out[-1][0] == fr:
            out[-1] = (fr, lv)
        else:
            out.append((fr, lv))
    return out


def env_level_at(pts, frame):
    fr = [x[0] for x in pts]
    lv = [x[1] for x in pts]
    return float(np.interp(frame, fr, lv))


def lfo_output(lfo, nframes, mod_at_frames):
    """Per-frame output of one program LFO (arm9 0x750b4 / 0x752f8 / waveform table 0x20b1250)."""
    raw = lfo['raw']
    mode = raw[1]
    wshape = raw[3]
    A = int.from_bytes(raw[4:8], 'little', signed=True) << 10
    depth = lfo['depth']
    out = np.zeros(nframes, dtype=np.float64)
    if depth == 0 or mode == 0:
        return out
    half = max(1, (depth * 1000) // 10000)
    slope = int(A / half)
    if mode == 1:
        delay = (lfo['delay'] * 1000) // 10000
        fade = (lfo['unk32'] * 1000) // 10000
        if fade:
            amp = 0
            ainc = 0x1000000 // fade
        else:
            amp = 0x1000000
            ainc = 0
        use_mod = False
    else:
        delay = 0
        fade = 0
        amp = 0
        ainc = 0
        use_mod = True
    value = 0
    counter = 0
    flag = 0
    rng = 0x1234567 ^ (A & 0xFFFF) ^ depth
    for f in range(nframes):
        if delay:
            delay -= 1
            continue
        # waveform step
        if wshape == 0:
            if counter == 0:
                counter = half
                value = 0 if value != 0 else A
            counter -= 1
        elif wshape == 1:
            if counter == 0:
                counter = half
                value = -A if flag & 2 else A
                flag ^= 2
            counter -= 1
        elif wshape == 2:
            if counter == 0:
                counter = half
                if flag & 1:
                    slope = -slope
                flag |= 1
            counter -= 1
            value += slope
        elif wshape == 3:
            if counter == 0:
                if flag & 1:
                    slope = -slope
                    n = half
                else:
                    n = max(1, half >> 1)
                flag |= 1
                counter = n
            counter -= 1
            value += slope
        elif wshape == 4:
            if counter:
                value += slope
            else:
                counter = half
                value = 0
            counter -= 1
        elif wshape == 5:
            if counter:
                value -= slope
            else:
                counter = half
                value = A
            counter -= 1
        elif wshape in (6, 7):
            if counter == 0:
                counter = half
                rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
                r = (rng >> 15) & 0x7FFF
                if wshape == 6:
                    value = r * (A >> 16)
                else:
                    value = r * (A >> 15) - (A >> 1)
            counter -= 1
        v = value >> 8
        if use_mod:
            a8 = int(mod_at_frames[f] * 256 / 127) << 16
        else:
            if fade:
                fade -= 1
                amp = 0x1000000 if fade == 0 else amp + ainc
            a8 = amp
        out[f] = ((a8 >> 8) * v) >> 16
    return out


# ----------------------------------------------------------------------------------------------
# Song rendering
# ----------------------------------------------------------------------------------------------
class Voice:
    __slots__ = ('note', 'split', 'sample', 't_on', 't_off', 't_end', 'pts', 'rel_frames', 'rel_level',
                 'vol16', 'bendrange', 'trk', 'kgrp', 'dead_frame', 'alive_end', 'kgprio')


def ctl_array(lst, nticks, default=0):
    lst = [(0, default)] + [x for x in lst if x[0] > 0 or True]
    # collapse same-tick entries (last wins)
    col = []
    for x in lst:
        if col and col[-1][0] == x[0]:
            col[-1] = x
        else:
            col.append(x)
    lst = col
    arr = np.empty(nticks + 1, dtype=np.float32)
    ticks = [x[0] for x in lst] + [nticks + 1]
    for k in range(len(lst)):
        a = min(ticks[k], nticks + 1)
        b = min(ticks[k + 1], nticks + 1)
        if b > a:
            arr[a:b] = lst[k][1]
    return arr


def lcm(a, b):
    return a * b // math.gcd(a, b)


class Song:
    def __init__(self, smd_path, swd_path, bank):
        self.smd = SMD(smd_path)
        self.swd = SWD(swd_path)
        self.bank = bank
        self.tpqn = self.smd.tpqn or 48
        self.warnings = []
        self.kgmap = {k['id']: k for k in getattr(self.swd, 'kgrps', [])}
        self.use_lfo = True
        self.max_voices = 16
        self.steals = []

    def has_notes(self):
        for t in self.smd.tracks:
            for o, c, a in parse_track_events(self.smd.d, t):
                if c < 0x80:
                    return True
        return False

    def analyse(self):
        """First pass without looping to find loop/end ticks per track."""
        info = []
        tempo = []
        for k, t in enumerate(self.smd.tracks):
            o = simulate_track(self.smd.d, t, 10 ** 8, tempo, k, loop_enabled=False)
            nnotes = len(o.notes)
            info.append((o.loop_tick, o.end_tick, nnotes))
        self.track_info = info
        loops = [(lp, end) for lp, end, n in info if lp is not None and end > lp]
        if not loops:
            self.looping = False
            self.S = None
            self.E = max(end for lp, end, n in info)
            self.L = None
            self.exact = True
            return
        self.looping = True
        S = max(lp for lp, end in loops)
        lens = sorted(set(end - lp for lp, end in loops))
        L = 1
        for x in lens:
            L = lcm(L, x)
        self.exact = True
        # consistency
        if len(lens) > 1:
            self.exact = False
        self.S = S
        self.lens = lens
        self.L = L

    def choose_loop(self, max_loop_s=240.0, target_s=60.0):
        tm_probe = None
        if not self.looping:
            return
        # need tempo map to evaluate seconds; run a quick sim to get tempo events
        tempo = []
        lim = self.S + max(self.lens) * 2 + 10
        for k, t in enumerate(self.smd.tracks):
            simulate_track(self.smd.d, t, lim, tempo, k)
        tm = TempoMap(tempo, self.tpqn)
        spt = float(np.median(tm.spt))
        if self.exact:
            return
        Lsec = self.L * spt
        if Lsec <= max_loop_s:
            self.exact = True  # LCM periodic: exact
            self.warnings.append('polyrhythmic track loops; using LCM period %.1fs' % Lsec)
            return
        # approximate: pick the period in [45 s, 120 s] where all track loops are closest to
        # completing a whole number of cycles (minimises the seam)
        lo = max(max(self.lens), int(45.0 / spt))
        hi = max(lo + 1, int(120.0 / spt))
        best = None
        for Lc in range(lo, hi + 1):
            cost = 0.0
            for x in self.lens:
                r = Lc % x
                cost += min(r, x - r) / float(x) * min(1.0, x * spt / 2.0)
            if best is None or cost < best[0] - 1e-9:
                best = (cost, Lc)
        self.L = best[1]
        self.warnings.append('polyrhythmic track loops (LCM %.0fs too long); approximate loop of %.1fs, seam may be audible'
                             % (Lsec, self.L * spt))

    def render(self, sr=32728, margin_s=12.0):
        self.analyse()
        self.choose_loop()
        smd = self.smd
        # simulation limit
        tempo = []
        if self.looping:
            E = self.S + self.L
            lim_ticks = self.S + 2 * self.L
        else:
            E = self.E
            lim_ticks = self.E
        # simulate with extra margin (in ticks; generous)
        margin_ticks = int(margin_s * 400)
        outs = []
        for k, t in enumerate(smd.tracks):
            outs.append(simulate_track(smd.d, t, lim_ticks + margin_ticks, tempo, k))
        tm = TempoMap(tempo, self.tpqn)
        self.tm = tm
        nticks = lim_ticks + margin_ticks + 2
        if self.looping:
            tS = float(tm.t(self.S))
            tE = float(tm.t(E))
            t2 = float(tm.t(E + self.L))
            pad = 0.15  # context for the resampler on both sides of each splice point
            windows = [(0.0, tS + pad), (max(0.0, tE - pad), t2 + pad)]
            total_t = t2 + pad
        else:
            tE = float(tm.t(E))
            windows = [(0.0, tE)]
            total_t = tE
            tS = None
        self.tS, self.tE = tS, tE
        # --- build voices ---
        notes = []
        for o in outs:
            notes.extend(o.notes)
        notes.sort(key=lambda n: (n.tick, n.trk, n.order))
        chan_of = [t.chan for t in smd.tracks]
        chans = sorted(set(chan_of))
        # controls live in the channel struct: merge events of all tracks sharing a channel
        ctl_ch = {}
        for ch in chans:
            members = [k for k in range(len(outs)) if chan_of[k] == ch]
            c = {}
            for name, dflt in CTL_DEFAULTS.items():
                ev = []
                for k in members:
                    ev.extend((tk, k, val) for tk, val in outs[k].ctl[name])
                ev.sort(key=lambda x: (x[0], x[1]))
                c[name] = ctl_array([(tk, val) for tk, k, val in ev], nticks, dflt)
            ctl_ch[ch] = c
        ctl = [ctl_ch[chan_of[k]] for k in range(len(outs))]
        self.ctl = ctl
        # kills (0x98 without loop) cut every voice of the channel alive at that tick
        kills = {}
        for k, o in enumerate(outs):
            if o.kill_tick is not None:
                kills.setdefault(chan_of[k], []).append(float(tm.t(o.kill_tick)))
        voices = []
        slots = [None] * self.max_voices
        progs = self.swd.programs
        default_kg = {'id': 0, 'poly': -1, 'prio': 8, 'lo': 0, 'hi': 255}
        self.dropped = 0
        for n in notes:
            prg = progs.get(n.prog)
            if prg is None:
                continue
            t_on = float(tm.t(n.tick))
            if t_on >= total_t:
                continue
            t_off = float(tm.t(n.off))
            ch = chan_of[n.trk]
            kl = [x for x in kills.get(ch, []) if x >= t_on - 1e-9]
            t_kill = min(kl) if kl else INF
            matched = [sp for sp in prg.splits
                       if sp.lowkey <= n.key <= sp.hikey and sp.lovel <= n.vel <= sp.hivel]
            for sp in matched:
                smp = self.bank.get(sp.smplid)
                if smp is None:
                    continue
                v = Voice()
                v.note = n
                v.split = sp
                v.sample = smp
                v.trk = n.trk
                v.kgrp = sp.kgrp
                envp = [sp.atkvol, sp.attack, sp.decay, sp.sustain, sp.hold, sp.decay2, sp.release]
                ov = n.envov
                if any(x <= 127 for x in ov):
                    envp = [ov[k] if ov[k] <= 127 else envp[k] for k in range(7)]
                mult = sp.envmult
                v.pts = envelope_breakpoints(envp, mult)
                v.t_on = t_on
                v.t_off = min(t_off, t_kill)
                relp = envp[6]
                rel_frame = int((v.t_off - t_on) / FRAME)
                v.rel_level = env_level_at(v.pts, rel_frame)
                rel_T = INF if relp == 0x7F else env_frames(relp, mult)
                v.rel_frames = (rel_frame, rel_T)
                end = t_on + (rel_frame + rel_T + 1) * FRAME if rel_T < INF else INF
                if v.pts[-1][1] <= 0 and v.pts[-1][0] < rel_frame:
                    end = min(end, t_on + v.pts[-1][0] * FRAME)
                if t_kill < INF:
                    end = min(end, t_kill)
                if not smp.loop:
                    tk0 = min(n.tick, nticks)
                    P0 = (n.key + sp.ktps + sp.ctune) * 256.0 + (sp.ftune & 0xFF) + ctl[n.trk]['tune'][tk0]
                    rate0 = 32728.0 * 2.0 ** ((P0 / 256.0 - 60.0) / 12.0)
                    end = min(end, t_on + smp.length / rate0 + 0.002)
                v.t_end = end
                v.vol16 = n.vel * prg.vol * sp.vol / 16129.0
                br = ctl[n.trk]['bendrange'][min(n.tick, nticks)]
                v.bendrange = int(br) if br else sp.bendrange
                # ---- voice allocation (arm9 0x74618) ----
                kg = self.kgmap.get(sp.kgrp, default_kg)
                prio = kg['prio']
                v.kgprio = prio
                lo = kg['lo']
                hi = min(kg['hi'], self.max_voices - 1)
                if lo > hi:
                    lo = 0
                new_word = (prio << 16) + 0x1FF

                def word(a):
                    if a is None or a.t_end <= t_on:
                        return 0
                    lv = int(self.level_at(a, t_on))
                    if t_on < a.t_off:
                        return (a.kgprio << 16) | 0x100 | lv
                    return lv

                use = None
                poly = kg['poly'] & 0xFF
                if kg['id'] != 0:
                    cnt = 0
                    best_w = new_word
                    best_c = hi
                    for ci in range(lo, hi + 1):
                        a = slots[ci]
                        if a is None or a.t_end <= t_on:
                            continue
                        if chan_of[a.trk] == ch and a.kgrp == v.kgrp:
                            cnt += 1
                            w = word(a)
                            if best_w > w:
                                best_w = w
                                best_c = ci
                            if cnt >= poly:
                                break
                    if cnt >= poly:
                        use = best_c
                if use is None:
                    cand = None
                    cmpw = new_word
                    for ci in range(lo, hi + 1):
                        w = word(slots[ci])
                        if cmpw > w:
                            cand = ci
                            if w == 0:
                                break
                            cmpw = w
                    use = cand
                if use is None:
                    self.dropped += 1
                    continue
                victim = slots[use]
                if victim is not None and victim.t_end > t_on:
                    self.steals.append(self.level_at(victim, t_on))
                    victim.t_end = t_on
                slots[use] = v
                voices.append(v)
        self.voices = voices
        # --- synthesize ---
        nout = int(math.ceil(total_t * sr)) + 2
        L = np.zeros(nout, dtype=np.float32)
        R = np.zeros(nout, dtype=np.float32)
        for v in voices:
            self.synth_voice(v, sr, windows, L, R, nticks)
        self.sr = sr
        return L, R

    def level_at(self, v, t):
        fr = (t - v.t_on) / FRAME
        rf, rT = v.rel_frames
        if fr < rf:
            return env_level_at(v.pts, fr)
        if rT >= INF:
            return v.rel_level
        if rT == 0:
            return 0.0
        x = (fr - rf) / rT
        return max(0.0, v.rel_level * (1 - x))

    def synth_voice(self, v, sr, windows, L, R, nticks):
        t0 = v.t_on
        t1 = min(v.t_end, windows[-1][1] + 0.0)
        if t1 <= t0:
            return
        # intersect with windows
        need = [(max(a, t0), min(b, t1)) for a, b in windows if min(b, t1) > max(a, t0)]
        if not need:
            return
        n0 = int(math.ceil(t0 * sr))
        n1 = int(math.ceil(t1 * sr))
        if n1 <= n0:
            return
        N = n1 - n0
        ts = (np.arange(n0, n1, dtype=np.float64)) / sr
        smp = v.sample
        sp = v.split
        c = self.ctl[v.trk]
        tk = self.tm.tick(ts)
        tki = np.minimum(tk.astype(np.int64), nticks)
        # pitch
        note = v.note
        base_key = np.full(N, note.key, dtype=np.float64)
        if len(note.keys) > 1:
            for (ktick, kk) in note.keys[1:]:
                kt = float(self.tm.t(ktick))
                base_key[ts >= kt] = kk
        P = (base_key + sp.ktps + sp.ctune) * 256.0 + (sp.ftune & 0xFF)
        tune = c['tune'][tki]
        bend = c['bend'][tki]
        P = P + tune + bend * (v.bendrange * 256.0 / 8192.0)
        # program LFOs (pitch / volume / pan), stepped at 100 Hz
        lfo_p = lfo_v = lfo_pan = None
        prg = self.swd.programs.get(note.prog)
        lfos = [x for x in (prg.lfos if prg else []) if x['raw'][1] and x['depth'] and x['dest'] in (1, 2, 3)]
        if lfos and self.use_lfo:
            nfr = int((ts[-1] - t0) / FRAME) + 2
            ftimes = t0 + np.arange(nfr) * FRAME
            ftk = np.minimum(self.tm.tick(ftimes).astype(np.int64), nticks)
            modf = c['mod'][ftk]
            acc = {1: np.zeros(nfr), 2: np.zeros(nfr), 3: np.zeros(nfr)}
            for x in lfos:
                acc[x['dest']] += lfo_output(x, nfr, modf)
            fpos = (ts - t0) / FRAME
            fidx = np.arange(nfr)
            if acc[1].any():
                lfo_p = np.interp(fpos, fidx, acc[1])
                P = P + lfo_p
            if acc[2].any():
                lfo_v = np.interp(fpos, fidx, np.floor(acc[2] / 64.0))
            if acc[3].any():
                lfo_pan = np.interp(fpos, fidx, np.floor(acc[3] / 64.0))
        rate = 32728.0 * np.exp2((P / 256.0 - 60.0) / 12.0)
        inc = rate / sr
        pos = np.cumsum(inc) - inc[0]
        # sample-start offset: first output sample is slightly after t_on
        pos += inc[0] * (n0 / sr - t0) * sr
        length = smp.length
        if smp.loop:
            ls = smp.loopstart
            ll = length - ls
            if ll <= 0:
                ll = 1
            over = pos >= length
            if over.any():
                pos = np.where(over, ls + np.mod(pos - ls, ll), pos)
        else:
            ok = pos < length - 1
            if not ok.all():
                cut = int(np.argmin(ok))
                if cut == 0:
                    return
                N = cut
                ts = ts[:N]
                tki = tki[:N]
                pos = pos[:N]
                n1 = n0 + N
        ip = pos.astype(np.int64)
        fr = (pos - ip).astype(np.float32)
        data = smp.data
        s = data[ip] * (1.0 - fr) + data[ip + 1] * fr
        # envelope
        frames = (ts - t0) / FRAME
        rf, rT = v.rel_frames
        ptsf = [p[0] for p in v.pts]
        ptsl = [p[1] for p in v.pts]
        env = np.interp(frames, ptsf, ptsl)
        rel = frames >= rf
        if rel.any():
            if rT >= INF:
                env[rel] = v.rel_level
            elif rT == 0:
                env[rel] = 0.0
            else:
                env[rel] = np.maximum(0.0, v.rel_level * (1.0 - (frames[rel] - rf) / rT))
        trk18 = c['vol'][tki] * c['expr'][tki] / 16129.0
        if lfo_v is not None:
            if len(lfo_v) != len(env):
                lfo_v = lfo_v[:len(env)]
            vol16 = np.clip(v.vol16 + lfo_v, 0, 127)
        else:
            vol16 = v.vol16
        amp = (env / 127.0) * (vol16 / 127.0) * trk18
        amp = amp * amp
        pan = sp.pan + c['pan'][tki] - 64
        if lfo_pan is not None:
            pan = pan + lfo_pan[:len(pan)]
        pan = np.clip(pan, 0, 127)
        sa = s * amp.astype(np.float32)
        L[n0:n1] += sa * ((128.0 - pan) / 128.0).astype(np.float32)
        R[n0:n1] += sa * (pan / 128.0).astype(np.float32)
