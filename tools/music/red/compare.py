#!/usr/bin/env python3
"""Compare a render against a reference rip: loudness, spectrum, tempo/offset (onset
cross-correlation over time-scale candidates) and pitch (chroma correlation)."""
import sys
import wave

import numpy as np

SR = 44100


def load(path):
    with wave.open(path) as w:
        n = w.getnframes()
        d = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.float32) / 32768.0
        d = d.reshape(-1, w.getnchannels())
    return d


def stft_mag(x, n=4096, hop=1024):
    win = np.hanning(n).astype(np.float32)
    frames = 1 + (len(x) - n) // hop
    idx = np.arange(n)[None, :] + hop * np.arange(frames)[:, None]
    return np.abs(np.fft.rfft(x[idx] * win, axis=1)), hop


def onset_env(x):
    S, hop = stft_mag(x, 2048, 512)
    L = np.log1p(100 * S)
    flux = np.maximum(0, np.diff(L, axis=0)).sum(axis=1)
    flux -= np.convolve(flux, np.ones(16) / 16, 'same')
    return np.maximum(flux, 0), hop


def chroma(x, n=8192, hop=2048):
    S, hop = stft_mag(x, n, hop)
    f = np.fft.rfftfreq(n, 1 / SR)
    ok = (f > 60) & (f < 2000)
    midi = 69 + 12 * np.log2(f[ok] / 440.0)
    pc = np.round(midi).astype(int) % 12
    C = np.zeros((S.shape[0], 12))
    P = S[:, ok] ** 2
    for k in range(12):
        C[:, k] = P[:, pc == k].sum(axis=1)
    C /= C.sum(axis=1, keepdims=True) + 1e-12
    return C, hop


def band_db(x):
    S, _ = stft_mag(x, 4096, 2048)
    P = (S ** 2).mean(axis=0)
    f = np.fft.rfftfreq(4096, 1 / SR)
    edges = [0, 100, 250, 500, 1000, 2000, 4000, 8000, 12000, 22050]
    tot = P.sum()
    return [10 * np.log10(P[(f >= a) & (f < b)].sum() / tot + 1e-12) for a, b in zip(edges, edges[1:])], edges


def main():
    ref = load(sys.argv[1])
    ren = load(sys.argv[2])
    rm = ref.mean(axis=1)
    sm = ren.mean(axis=1)
    rms = lambda a: 20 * np.log10(np.sqrt(np.mean(a ** 2)) + 1e-12)
    print('duration ref %.2f  ren %.2f' % (len(rm) / SR, len(sm) / SR))
    print('RMS dBFS ref %.2f  ren %.2f   peak ref %.3f ren %.3f' % (rms(ref), rms(ren), np.abs(ref).max(), np.abs(ren).max()))
    # stereo width
    for nm, a in (('ref', ref), ('ren', ren)):
        mid = (a[:, 0] + a[:, 1]) / 2
        side = (a[:, 0] - a[:, 1]) / 2
        print('  %s side/mid dB %.1f  L-R balance dB %.2f' % (nm, rms(side) - rms(mid), rms(a[:, 0]) - rms(a[:, 1])))
    br, edges = band_db(rm)
    bs, _ = band_db(sm[:len(rm)])
    print('band energy (dB rel total):')
    for a, b, x, y in zip(edges, edges[1:], br, bs):
        print('  %5d-%5d  ref %6.1f  ren %6.1f  diff %+5.1f' % (a, b, x, y, y - x))
    # tempo/offset
    oe_r, hop = onset_env(rm)
    oe_s, _ = onset_env(sm)
    best = None
    seg = min(len(oe_r), int(40 * SR / hop))
    for scale in np.arange(0.985, 1.0151, 0.0005):
        t = np.arange(len(oe_s)) * scale
        ss = np.interp(np.arange(seg + 400), t, oe_s, right=0)
        r = oe_r[:seg]
        cc = np.correlate(ss, r, 'valid') if False else None
        # try offsets -200..+200 frames
        sc = []
        for off in range(-25, 26):
            a = r[max(0, -off):seg]
            b = ss[max(0, off):max(0, off) + len(a)]
            m = min(len(a), len(b))
            sc.append(np.dot(a[:m], b[:m]) / (np.linalg.norm(a[:m]) * np.linalg.norm(b[:m]) + 1e-9))
        k = int(np.argmax(sc))
        if abs(scale - 1) < 1e-6:
            print('  at scale 1.0: corr@0 %.3f  best %.3f @ %+.3f s' % (sc[25], sc[k], (k - 25) * hop / SR))
        if best is None or sc[k] > best[0]:
            best = (sc[k], scale, k - 25)
    print('onset match: corr %.3f  time scale ren->ref %.4f  offset %+.3f s' % (best[0], best[1], best[2] * hop / SR))
    # chroma with alignment
    scale, off = best[1], best[2] * hop / SR
    Cr, h = chroma(rm)
    Cs, _ = chroma(sm)
    tr = np.arange(len(Cr)) * h / SR
    # ren time corresponding to ref time t: (t + off)/scale  (approx)
    ts = (tr + off) / scale
    js = np.clip(np.round(ts * SR / h).astype(int), 0, len(Cs) - 1)
    valid = ts * SR / h < len(Cs) - 1
    res = []
    for shift in range(12):
        A = Cr[valid]
        B = np.roll(Cs[js[valid]], shift, axis=1)
        num = (A * B).sum(axis=1)
        den = np.linalg.norm(A, axis=1) * np.linalg.norm(B, axis=1) + 1e-12
        res.append(np.mean(num / den))
    print('chroma cosine by semitone shift (ren rolled):', ' '.join('%d:%.3f' % (i, v) for i, v in enumerate(res)))
    # per segment chroma similarity (first 30s, by 5s)
    A = Cr[valid]
    B = Cs[js[valid]]
    sim = (A * B).sum(axis=1) / (np.linalg.norm(A, axis=1) * np.linalg.norm(B, axis=1) + 1e-12)
    tv = tr[valid]
    out = []
    for s in range(0, int(tv[-1]), 5):
        m = (tv >= s) & (tv < s + 5)
        if m.any():
            out.append('%d:%.2f' % (s, sim[m].mean()))
    print('chroma sim per 5s:', ' '.join(out))


if __name__ == '__main__':
    main()
