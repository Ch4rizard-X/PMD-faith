"""Render Explorers of Sky BGM (SOUND/BGM/bgmNNNN.smd + .swd + bgm.swd) to game/assets/music/eos_NNNN.ogg
and game/data/eos_loops.json.

Loop points come from the sequence data itself: the DSE loop-point event (0x99) and the track end (0x98)
give the loop start / end ticks, converted to seconds with the tempo map (render.py Song.tS / Song.tE).
Looping tracks are written as intro + exactly one loop period, so the game loops from loop_start to the end.

usage: python3 -I make.py [OUTDIR] [ids,comma,sep] [--gain G] [--wav]
"""
import sys
import os
import json
import math
import time
import subprocess
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
import common  # noqa: E402
from audio_util import resample  # noqa: E402
from samples import load_bank  # noqa: E402
from render import Song  # noqa: E402

BGM = os.path.join(common.EOS, 'fs', 'SOUND', 'BGM')
CACHE = os.path.join(common.TMP, 'eos_bgm_cache')
SR_SYN = 32728
SR_OUT = 24000
# bgm0124's own swd lacks the programs its sequence uses (51/59); it is a near copy of bgm0000
SWD_OVERRIDE = {124: 0}


def render_one(num, bank, gain, outdir, keep_wav=False):
    smd = os.path.join(BGM, 'bgm%04d.smd' % num)
    swd = os.path.join(BGM, 'bgm%04d.swd' % SWD_OVERRIDE.get(num, num))
    song = Song(smd, swd, bank)
    if not song.has_notes():
        return None
    L, R = song.render(sr=SR_SYN)
    st = np.stack([L, R], axis=1).astype(np.float64)
    # resample whole render (incl. pass 2/3 context) before splicing
    y = resample(st, SR_SYN, SR_OUT)
    if song.looping:
        S = int(round(song.tS * SR_OUT))
        E = int(round(song.tE * SR_OUT))
        Lp = E - S
        body = y[E:E + Lp]
        if len(body) < Lp:
            body = np.concatenate([body, np.zeros((Lp - len(body), 2))])
        out = np.concatenate([y[:S], body])
        loop_start = S / SR_OUT
    else:
        E = int(round(song.tE * SR_OUT))
        out = y[:E]
        # trim trailing digital silence, keep natural end
        a = np.abs(out).max(axis=1)
        nz = np.nonzero(a > 1e-5)[0]
        if len(nz):
            out = out[:nz[-1] + int(0.05 * SR_OUT)]
        # 5 ms fade at the very end to avoid a click from hard cuts
        nf = min(len(out), int(0.005 * SR_OUT))
        if nf > 0:
            out[-nf:] *= np.linspace(1, 0, nf)[:, None]
        loop_start = None
    out = out * gain
    peak = float(np.abs(out).max()) if len(out) else 0.0
    limited = None
    if peak > 0.97:
        limited = 0.97 / peak
        out = out * limited
        peak = 0.97
    rms = float(np.sqrt(np.mean(out ** 2))) if len(out) else 0.0
    clipped = int((np.abs(out) > 0.999).sum())
    pcm = (np.clip(out, -1, 1) * 32767).astype('<i2')
    wav = os.path.join(outdir, '_tmp_%04d.raw' % num)
    pcm.tofile(wav)
    ogg = os.path.join(outdir, 'eos_%04d.ogg' % num)
    subprocess.run(['nice', '-n', '19', 'ffmpeg', '-nostdin', '-y', '-loglevel', 'error', '-f', 's16le', '-ar',
                    str(SR_OUT), '-ac', '2', '-i', wav, '-c:a', 'libvorbis', '-q:a', '0', ogg], check=True)
    if keep_wav:
        os.replace(wav, wav.replace('.raw', '.s16'))
    else:
        os.remove(wav)
    return dict(loop_start=loop_start, length=len(out) / SR_OUT, peak=peak, rms=rms, clipped=clipped,
                limited=limited, steals=len(song.steals), dropped=song.dropped,
                warnings=song.warnings, voices=len(song.voices), looping=song.looping,
                exact=getattr(song, 'exact', True))


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    keep = '--wav' in argv
    args = [a for a in argv if a not in ('--wav', '--resume')]
    outdir = os.path.join(common.ASSETS, 'music')
    if args and not args[0][0].isdigit() and not args[0].startswith('--'):
        outdir = args.pop(0)
    os.makedirs(outdir, exist_ok=True)
    ids = None
    gain = 0.7          # level of the shipped renders (stats_final: rms 0.0274 for bgm0000)
    if '--gain' in args:
        k = args.index('--gain')
        gain = float(args[k + 1])
        del args[k:k + 2]
    if args:
        ids = [int(x) for x in args[0].split(',')]
    else:
        ids = sorted(int(f[3:7]) for f in os.listdir(BGM) if f.endswith('.smd'))
    bank = load_bank(os.path.join(BGM, 'bgm.swd'), CACHE)
    statf = os.path.join(CACHE, '_stats.json')
    stats = json.load(open(statf)) if os.path.exists(statf) else {}
    skip_done = '--resume' in argv
    for num in ids:
        t0 = time.time()
        if skip_done and 'length' in stats.get('%04d' % num, {}) and os.path.exists(os.path.join(outdir, 'eos_%04d.ogg' % num)):
            continue
        try:
            r = render_one(num, bank, gain, outdir, keep)
        except Exception as e:
            import traceback
            traceback.print_exc()
            stats['%04d' % num] = {'error': repr(e)}
            print('%04d FAILED %r' % (num, e), flush=True)
            continue
        if r is None:
            stats['%04d' % num] = {'skipped': 'no notes'}
            print('%04d no notes' % num, flush=True)
            continue
        stats['%04d' % num] = r
        print('%04d len=%.1fs loop=%s peak=%.3f rms=%.4f clip=%d voices=%d %.1fs %s' % (
            num, r['length'], None if r['loop_start'] is None else round(r['loop_start'], 2), r['peak'], r['rms'],
            r['clipped'], r['voices'], time.time() - t0, '; '.join(r['warnings'])), flush=True)
        json.dump(stats, open(statf, 'w'), indent=1)
    write_loops(stats)


def write_loops(stats, path=None):
    """data/eos_loops.json: {"NNNN": {"loop_start": s or null, "length": s}} for every rendered track."""
    out = {}
    for k in sorted(stats):
        r = stats[k]
        if 'length' in r:
            out[k] = {'loop_start': None if r['loop_start'] is None else round(r['loop_start'], 6),
                      'length': round(r['length'], 6)}
    common.save_json(path or os.path.join(common.DATA, 'eos_loops.json'), out, pretty=True)
    return out


if __name__ == '__main__':
    main()
