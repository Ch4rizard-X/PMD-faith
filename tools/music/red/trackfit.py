#!/usr/bin/env python3
"""Render each track solo (fixed gain) and fit per-track power gains so that the sum of
solo band-power spectrograms best matches the reference rip (NNLS). Gains far from a
common value indicate per-voice level errors in the renderer.
usage: trackfit.py NNN ref.wav [seconds]"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy.optimize import nnls

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare import load, stft_mag, SR  # noqa

num = int(sys.argv[1])
ref = load(sys.argv[2]).mean(axis=1)
secs = float(sys.argv[3]) if len(sys.argv) > 3 else 45
here = os.path.dirname(os.path.abspath(__file__))
info = json.loads(subprocess.check_output(['python3', os.path.join(here, 'render.py'), str(num), '/dev/null', '--gain', '1'] if False else
                                          ['python3', '-c', 'import sys; sys.path.insert(0,"%s"); import render; s=render.Song(%d); print(s.ntracks)' % (here, num)]))
ntr = int(info)
n = int(secs * SR)
edges = np.geomspace(40, 16000, 25)
f = np.fft.rfftfreq(4096, 1 / SR)


def feats(x):
    x = x[:n]
    if len(x) < n:
        x = np.concatenate([x, np.zeros(n - len(x))])
    S, _ = stft_mag(x.astype(np.float32), 4096, 2048)
    P = S ** 2
    return np.stack([P[:, (f >= a) & (f < b)].sum(axis=1) for a, b in zip(edges, edges[1:])], axis=1)


cols = []
for k in range(ntr):
    out = os.path.join(here, 'tmp', 'solo_%03d_%02d.wav' % (num, k))
    env = dict(os.environ, M4A_SOLO=str(k))
    subprocess.check_call(['python3', os.path.join(here, 'render.py'), str(num), out, '--gain', '1'], env=env,
                          stdout=subprocess.DEVNULL)
    cols.append(feats(load(out).mean(axis=1)))
R = feats(ref)
# compress dynamic range a bit: fit on power^0.5 is not linear; keep power but weight by band
A = np.stack([c.ravel() for c in cols], axis=1)
b = R.ravel()
w = 1.0 / (R.mean(axis=0, keepdims=True).repeat(R.shape[0], 0).ravel() + 1e-12)
g, res = nnls(A * w[:, None], b * w)
tot = np.array([c.sum() for c in cols])
print('track  gain(dB, rel median)  energy share')
med = np.median(g[g > 0]) if (g > 0).any() else 1
for k in range(ntr):
    print('%3d  %+7.1f dB   %.3f' % (k, 10 * np.log10(g[k] / med + 1e-12), tot[k] / tot.sum()))
print('overall power gain median: %.4g (%.1f dB amplitude)' % (med, 10 * np.log10(med)))
