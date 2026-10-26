#!/usr/bin/env python3
"""Copy the decoded ground maps (gen_ground_bg.py output) into the Godot project.

  assets/ground/<name>.png             native layers (+ animation overlay frames)
  assets/ground/*.json                 index, collision, terrain
  assets/ground/hd/<layer>_hd.webp     4x xBRZ layers as lossy WebP (quality 88) to keep the APK small
Palette-index images and palette lists are not copied (the overlays cover palette animation).
"""
import json, os, shutil, sys
from PIL import Image

SRC = "/tmp/claude-0/pmd1/ground_bg"
DST = "/tmp/claude-0/pmd1/game/assets/ground"
os.makedirs(DST + "/hd", exist_ok=True)
idx = json.load(open(os.path.join(SRC, "index.json")))
want = set()
for name, e in idx.items():
    for l in e.get("layers", []):
        want.add(l)
    for k in ("collision", "terrain"):
        if e.get(k):
            want.add(e[k])
    an = e.get("anim", {})
    for t in an.get("tiles", []):
        for fr in t.get("frames", []):
            for lf in fr.values():
                want.add(lf["file"])
    for p in an.get("palettes", []):
        for fr in p.get("overlays", []):
            for lf in fr.values():
                want.add(lf["file"])
n = 0
for f in sorted(want):
    s = os.path.join(SRC, f)
    if not os.path.exists(s):
        print("missing", f)
        continue
    d = os.path.join(DST, f)
    if not os.path.exists(d) or os.path.getmtime(d) < os.path.getmtime(s):
        shutil.copyfile(s, d)
        n += 1
shutil.copyfile(os.path.join(SRC, "index.json"), os.path.join(DST, "index.json"))
hd = 0
if "--no-hd" not in sys.argv:
    for name, e in idx.items():
        for l in e.get("layers", []):
            b = l[:-4]
            s = os.path.join(SRC, b + "_hd.png")
            d = os.path.join(DST, "hd", b + "_hd.webp")
            if os.path.exists(s) and (not os.path.exists(d) or os.path.getmtime(d) < os.path.getmtime(s)):
                Image.open(s).save(d, "WEBP", quality=88, method=4)
                hd += 1
tot = 0
for root, _, fs in os.walk(DST):
    for f in fs:
        tot += os.path.getsize(os.path.join(root, f))
print("copied", n, "hd", hd, "total MB", round(tot / 1e6, 1))
