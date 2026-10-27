#!/usr/bin/env python3
"""Compare the ground area's outputs with a reference game folder (pass its path, read only).

usage: python3 -I tools/ground/compare.py [REF_GAME_DIR] [--no-audio]
Per folder: file names (Godot *.import files ignored), images pixel-compared (decoded RGBA), JSON compared
structurally, audio compared by duration and similarity (EoS: waveform correlation; Red music / SE: correlation of
log-band spectrogram envelopes, since the old Red files were renders from a different synthesizer).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "music"))
import common  # noqa: E402

REF = next((a for a in sys.argv[1:] if not a.startswith("--")), os.environ.get("REF_GAME", ""))
OURS = common.GAME
IMG = (".png", ".webp")


def files(root, sub):
    base = os.path.join(root, sub)
    out = set()
    for r, _, fs in os.walk(base):
        for f in fs:
            if not f.endswith(".import"):
                out.add(os.path.relpath(os.path.join(r, f), base))
    return out


def pix(path):
    a = np.array(Image.open(path).convert("RGBA"))
    a[a[..., 3] == 0] = 0          # colour of fully transparent pixels does not matter
    return a


def cmp_images(sub, names, skip=()):
    same, diff = 0, []
    for n in sorted(names):
        if n in skip or not n.endswith(IMG):
            continue
        a, b = pix(os.path.join(OURS, sub, n)), pix(os.path.join(REF, sub, n))
        if a.shape == b.shape and np.array_equal(a, b):
            same += 1
        else:
            if a.shape != b.shape:
                diff.append((n, "size %s vs %s" % (a.shape[:2], b.shape[:2])))
            else:
                m = (a != b).any(axis=2)
                diff.append((n, "%.2f%% px differ" % (100 * m.mean())))
    return same, diff


def folder(sub, skip=(), show=12):
    a, b = files(OURS, sub), files(REF, sub)
    print("\n## %s: ours %d files, reference %d" % (sub, len(a), len(b)))
    if a - b:
        print("  only ours:", sorted(a - b)[:show], "..." if len(a - b) > show else "")
    if b - a:
        print("  only reference:", sorted(b - a)[:show], "..." if len(b - a) > show else "")
    same, diff = cmp_images(sub, a & b, skip)
    print("  images identical: %d, different: %d" % (same, len(diff)))
    for n, why in diff[:show]:
        print("    %s: %s" % (n, why))
    js = [n for n in sorted(a & b) if n.endswith(".json")]
    if js:
        eq = [n for n in js if json.load(open(os.path.join(OURS, sub, n))) == json.load(open(os.path.join(REF, sub, n)))]
        print("  json identical: %d / %d %s" % (len(eq), len(js), sorted(set(js) - set(eq))[:show]))
    return a, b


def data_json(name):
    a, b = os.path.join(OURS, "data", name), os.path.join(REF, "data", name)
    if not os.path.exists(a):
        print("  data/%s: MISSING" % name)
        return None, None
    A, B = json.load(open(a)), json.load(open(b))
    print("  data/%s: %s" % (name, "identical" if A == B else "differs"))
    return A, B


def town():
    import base64
    A, B = data_json("town.json")
    if A is None:
        return
    for sec in ("maps", "bases"):
        for k in B[sec]:
            a, b = A[sec].get(k), B[sec][k]
            if a is None:
                print("   %s %s missing" % (sec, k))
                continue
            keys = set(a) | set(b)
            same = [x for x in keys if x not in ("grid", "anim", "tex", "k") and a.get(x) == b.get(x)]
            other = sorted(x for x in keys if x not in same)
            line = "   %s/%s: layout keys equal %d, differ/new %s" % (sec, k, len(same), other)
            if "grid" in a and "grid" in b:
                def g(x):
                    bits = np.unpackbits(np.frombuffer(base64.b64decode(x["b64"]), np.uint8), bitorder="little")
                    return bits[:x["W"] * x["H"]].reshape(x["H"], x["W"]).astype(bool)
                ga, gb = g(a["grid"]), g(b["grid"])
                line += "; walk grid agreement %.1f%%" % (100 * (ga == gb).mean())
            if "anim" in a and "anim" in b:
                line += "; anim frames %d (ref %d), lap %d ms (ref %d)" % (
                    len(a["anim"]["dur"]), len(b["anim"]["dur"]), sum(a["anim"]["dur"]), sum(b["anim"]["dur"]))
            print(line)


def feats(y, sr):
    n, hop = 1024, 512
    if len(y) < n:
        y = np.pad(y, (0, n - len(y)))
    fr = 1 + (len(y) - n) // hop
    idx = np.arange(n)[None, :] + hop * np.arange(fr)[:, None]
    S = np.abs(np.fft.rfft(y[idx] * np.hanning(n), axis=1)) ** 2
    f = np.fft.rfftfreq(n, 1 / sr)
    edges = np.geomspace(60, min(10000, sr / 2 - 1), 25)
    E = np.stack([S[:, (f >= a) & (f < b)].sum(1) for a, b in zip(edges, edges[1:])], 1)
    L = np.log10(E + 1e-8)
    return np.maximum(L - L.max(), -5) + 5


def sim(a, b, sr):
    A, B = feats(a, sr), feats(b, sr)
    m = min(len(A), len(B))
    A, B = A[:m].ravel(), B[:m].ravel()
    return float(A @ B / (np.linalg.norm(A) * np.linalg.norm(B) + 1e-9))


def audio(sub, names, mode_of):
    from audio_util import decode
    rows = []
    stem = lambda s: s.rsplit(".", 1)[0]
    ref = {stem(n): n for n in files(REF, sub)}
    for n in sorted(names):
        r = ref.get(stem(n))
        if r is None:
            continue
        sr = 16000
        a = decode(os.path.join(OURS, sub, n), sr, mono=True)
        b = decode(os.path.join(REF, sub, r), sr, mono=True)
        mode = mode_of(n)
        if np.abs(b).max() < 1e-4:
            rows.append((n, len(a) / sr, len(b) / sr, None, "reference is silent"))
            continue
        if mode == "wave":
            m = min(len(a), len(b))
            c = float(a[:m] @ b[:m] / (np.linalg.norm(a[:m]) * np.linalg.norm(b[:m]) + 1e-9))
        else:
            c = sim(a[:sr * 60], b[:sr * 60], sr)
        rows.append((n, len(a) / sr, len(b) / sr, c, ""))
    return rows


def report_audio(title, rows, show=10):
    vals = [r[3] for r in rows if r[3] is not None]
    print("  %s: %d compared, similarity median %.3f, min %.3f" % (title, len(rows), float(np.median(vals)),
                                                                 float(min(vals))))
    for r in sorted(rows, key=lambda r: (r[3] if r[3] is not None else -1))[:show]:
        print("    %-14s ours %6.2fs ref %6.2fs sim %s %s" % (r[0], r[1], r[2],
                                                            "-" if r[3] is None else "%.3f" % r[3], r[4]))


def main():
    print("reference:", REF)
    folder("assets/ground")
    folder("data/ground")
    data_json("red_credits.json")
    folder("assets/town")
    town()
    folder("assets/worldmap")
    data_json("world_map.json")
    ours_ui, _ = folder("assets/ui")
    data_json("eos_loops.json")
    if "--no-audio" in sys.argv:
        return
    a, b = files(OURS, "assets/music"), files(REF, "assets/music")
    stem = lambda s: s.rsplit(".", 1)[0]
    print("\n## assets/music: ours %d, reference %d; stems only ours %s, only ref %s" % (
        len(a), len(b), sorted({stem(x) for x in a} - {stem(x) for x in b}),
        sorted({stem(x) for x in b} - {stem(x) for x in a})))
    rows = audio("assets/music", a, lambda n: "wave" if n.startswith("eos_") else "spec")
    report_audio("Explorers of Sky (waveform corr.)", [r for r in rows if r[0].startswith("eos_")])
    report_audio("Red (spectral envelope)", [r for r in rows if not r[0].startswith("eos_")])
    a, b = files(OURS, "assets/sfx"), files(REF, "assets/sfx")
    print("\n## assets/sfx: ours %d, reference %d, only ours %s, only ref %s" % (len(a), len(b), sorted(a - b), sorted(b - a)))
    report_audio("Red SE (spectral envelope)", audio("assets/sfx", a, lambda n: "spec"))


if __name__ == "__main__":
    main()
