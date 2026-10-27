#!/usr/bin/env python3
"""Render Red Rescue Team songs from the pret/pmd-red decomp (sound/songs, voicegroups, wave) with render.py.

  BGM  -> game/assets/music/NNN.ogg   (24 kHz Vorbis q0, like the other music files)
          looping songs: intro (pass 1, [0, loop start)) + exactly one loop period taken from pass 2, so the file
          loops seamlessly from its loop start; loop points come from the sequence (track 0 GOTO target / GOTO).
          They are also stored as "red_NNN" entries in data/eos_loops.json (see audio.gd note in the report).
  SE   -> game/assets/sfx/<name>.(ogg|mp3)  one pass (+ release tail), trailing silence trimmed.

usage: python3 -I make.py bgm [ids]      ids like 1,7,110 (default: all BGM the game uses)
       python3 -I make.py se  [ids]
"""
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
import common  # noqa: E402
import render  # noqa: E402
from audio_util import resample, encode  # noqa: E402

SR_OUT = 24000
# BGM ids the game ships (Red's song table 1-127 that have music; 128 = Monster House)
BGM_IDS = list(range(1, 47)) + [50, 51, 52] + list(range(100, 129))
# The shipped music sits at about -19.5 dBFS RMS (mono mix); SE at their own level (see SE_RMS_DB).
BGM_RMS_DB = -19.5
STATS = os.path.join(common.TMP, "red_music_stats.json")


def _rms_db(st):
    m = st.mean(axis=1)
    return 20 * np.log10(np.sqrt(np.mean(m ** 2)) + 1e-12)


def _norm(st, target_db, peak=0.97):
    g = 10 ** ((target_db - _rms_db(st)) / 20.0)
    st = st * g
    pk = float(np.abs(st).max()) if len(st) else 0
    if pk > peak:
        st *= peak / pk
    return st


def render_song(num, loops=2, tail=1.0):
    p = render.Player(num, loops=loops, tail=tail)
    L, R = p.run()
    st = np.stack([L, R], axis=1).astype(np.float64)
    spf = render.OUT_RATE / render.FRAME_RATE
    ls = p.loop_start_frame * spf / render.OUT_RATE if p.loop_start_frame is not None else None
    le = p.goto_frames[0] * spf / render.OUT_RATE if p.goto_frames else None
    return st, ls, le


def bgm(num, outdir):
    st, ls, le = render_song(num)
    y = resample(st, render.OUT_RATE, SR_OUT)
    if ls is not None and le is not None and le > ls:
        S, E = int(round(ls * SR_OUT)), int(round(le * SR_OUT))
        Lp = E - S
        body = y[E:E + Lp]
        if len(body) < Lp:
            body = np.concatenate([body, np.zeros((Lp - len(body), 2))])
        out = np.concatenate([y[:S], body])
        loop_start = S / SR_OUT
    else:
        out = _trim(y)
        loop_start = None
    out = _norm(out, BGM_RMS_DB)
    encode(out, SR_OUT, os.path.join(outdir, "%03d.ogg" % num))
    return {"loop_start": None if loop_start is None else round(loop_start, 6), "length": round(len(out) / SR_OUT, 6)}


def _trim(y, thr=1e-4, keep=0.05):
    a = np.abs(y).max(axis=1)
    nz = np.nonzero(a > thr)[0]
    if len(nz):
        y = y[:nz[-1] + int(keep * SR_OUT)]
    nf = min(len(y), int(0.005 * SR_OUT))
    if nf:
        y = y.copy()
        y[-nf:] *= np.linspace(1, 0, nf)[:, None]
    return y


def se(num, path, sr=None, target_db=None, max_s=12.0, gain=1.0):
    """One sound effect. Looping SEs (GOTO) are rendered once through their loop and cut at max_s."""
    st, ls, le = render_song(num, loops=1, tail=0.5)
    st = st[:int(max_s * render.OUT_RATE)]
    sr = sr or (44100 if path.endswith(".mp3") else SR_OUT)
    y = resample(st, render.OUT_RATE, sr) if sr != render.OUT_RATE else st
    a = np.abs(y).max(axis=1)
    nz = np.nonzero(a > 1e-4)[0]
    if len(nz):
        y = y[nz[0]:]            # the rips start at the first sound
    y = _trim(y) * gain
    if target_db is not None:
        y = _norm(y, target_db)
    else:
        pk = float(np.abs(y).max()) if len(y) else 0
        if pk > 0.97:
            y *= 0.97 / pk
    encode(y, sr, path, codec="mp3" if path.endswith(".mp3") else "ogg")
    return len(y) / sr


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    kind = argv[0] if argv else "bgm"
    ids = [int(x) for x in argv[1].split(",")] if len(argv) > 1 else None
    if kind == "bgm":
        outdir = os.path.join(common.ASSETS, "music")
        os.makedirs(outdir, exist_ok=True)
        stats = common.load_json(STATS) if os.path.exists(STATS) else {}
        for num in ids or BGM_IDS:
            t0 = time.time()
            stats["%03d" % num] = bgm(num, outdir)
            print("%03d %s %.1fs" % (num, stats["%03d" % num], time.time() - t0), flush=True)
            common.save_json(STATS, stats, pretty=True)
    else:
        sys.exit("SE rendering is driven by tools/music/sfx.py")


if __name__ == "__main__":
    main()
