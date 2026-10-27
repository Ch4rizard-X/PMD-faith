#!/usr/bin/env python3
"""Copy the decoded ground maps (gen_ground_bg.py output in common.TMP/ground_bg) into the Godot project.

  assets/ground/<name>.png             native layers, tile-animation overlay frames, palette-index images
  assets/ground/*.json                 index, collision, terrain
  assets/ground/hd/<layer>_hd.webp     4x xBRZ layers as lossy WebP (quality 88) to keep the APK small
"""
import json
import os
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

SRC = os.path.join(common.TMP, "ground_bg")
DST = os.path.join(common.ASSETS, "ground")


def wanted(idx):
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
        # palette cycling is drawn by the game from <layer>_idx.png + the colour lists (shader), so the
        # per-frame palette overlay PNGs gen_ground_bg.py also writes are not copied
        for f in an.get("index_images", {}).values():
            want.add(f)
    return want


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    os.makedirs(os.path.join(DST, "hd"), exist_ok=True)
    idx = json.load(open(os.path.join(SRC, "index.json")))
    n = 0
    for f in sorted(wanted(idx)):
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
    if "--no-hd" not in argv:
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
    print("ground assets: copied", n, "hd", hd, "total MB", round(tot / 1e6, 1))


if __name__ == "__main__":
    main()
