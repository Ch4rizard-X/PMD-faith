"""Decode the DSE main sample bank (bgm.swd) to float32 PCM, cached."""
import os
import numpy as np
from dse import SWD

IDX = [-1, -1, -1, -1, 2, 4, 6, 8]
STEP = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
        107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
        4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
        22385, 24623, 27086, 29794, 32767]


def adpcm_decode(data):
    last = int.from_bytes(data[0:2], 'little', signed=True)
    si = data[2] & 0x7F
    out = np.empty((len(data) - 4) * 2, dtype=np.int16)
    k = 0
    for b in data[4:]:
        for val in (b & 0xF, b >> 4):
            step = STEP[si]
            diff = step >> 3
            if val & 1:
                diff += step >> 2
            if val & 2:
                diff += step >> 1
            if val & 4:
                diff += step
            if val & 8:
                last -= diff
                if last < -32768:
                    last = -32768
            else:
                last += diff
                if last > 32767:
                    last = 32767
            si += IDX[val & 7]
            if si < 0:
                si = 0
            elif si > 88:
                si = 88
            out[k] = last
            k += 1
    return out


class Sample:
    pass


def load_bank(path, cache_dir):
    swd = SWD(path)
    os.makedirs(cache_dir, exist_ok=True)
    cache = os.path.join(cache_dir, 'bank.npz')
    pcmo, pcml = swd.pcm
    d = swd.d
    res = {}
    arrays = {}
    if os.path.exists(cache):
        z = np.load(cache)
        arrays = {int(k[1:]): z[k] for k in z.files}
    for i, w in swd.wavs.items():
        s = Sample()
        s.wav = w
        nbytes = (w.loopbeg + w.looplen) * 4
        raw = d[pcmo + w.smplpos: pcmo + w.smplpos + nbytes]
        if w.fmt == 0x200:
            ls = (w.loopbeg - 1) * 8 if w.loopbeg > 0 else 0
        elif w.fmt == 0x100:
            ls = w.loopbeg * 2
        elif w.fmt == 0x000:
            ls = w.loopbeg * 4
        else:
            raise ValueError('fmt %x' % w.fmt)
        if i not in arrays:
            if w.fmt == 0x200:
                pcm = adpcm_decode(raw)
            elif w.fmt == 0x100:
                pcm = np.frombuffer(raw, dtype='<i2').copy()
            else:
                pcm = (np.frombuffer(raw, dtype='i1').astype(np.int16) << 8)
            arrays[i] = pcm
        pcm = arrays[i]
        s.length = len(pcm)
        s.loop = bool(w.loop)
        s.loopstart = min(max(ls, 0), max(len(pcm) - 1, 0))
        f = pcm.astype(np.float32) / 32768.0
        # extended copy for interpolation: one guard sample
        if s.loop and s.length - s.loopstart >= 1:
            guard = f[s.loopstart:s.loopstart + 1]
        else:
            guard = np.zeros(1, np.float32)
        s.data = np.concatenate([f, guard])
        res[i] = s
    if not os.path.exists(cache):
        np.savez(cache, **{'s%d' % k: v for k, v in arrays.items()})
    return res
