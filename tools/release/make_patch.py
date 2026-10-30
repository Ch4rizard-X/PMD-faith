#!/usr/bin/env python3
"""Build a script patch (patch.zip + patch.json) for the in-game updater (game/scripts/core/patcher.gd).

A patch holds ONLY the open-source files of the Godot project that are tracked in this repository:
scripts (.gd), scenes (.tscn/.tres) and shaders. Each file gets a "<file>.remap" pointing at itself, so the
text file in the patch is used instead of the compiled copy (.gdc / .scn) inside the exported game.
It never contains game data, graphics, music or anything else built from the ROMs.

Changes that can't ship as a patch need a new APK / exe and a higher BASE_REV in patcher.gd:
game data or assets, the asset tools, project.godot, the Android plugin, a Godot upgrade, patcher.gd itself,
or a new class_name (exported games only know the classes they were built with). This script refuses to build
a patch with a class_name the base doesn't know (tools/release/base_classes.json, rewritten with --new-base).

  python3 tools/release/make_patch.py --out dist --url https://github.com/<you>/<repo>/releases/download/v0.8.13
"""
import argparse, hashlib, json, os, re, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = os.path.join(ROOT, "game")
EXTS = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc")
SKIP_DIRS = ("tests/", "addons/")
# patcher.gd runs before any patch; the setup screen belongs to each exe (MD-Recomp ships its own, newer one)
SKIP_FILES = ("scripts/core/patcher.gd", "scripts/ui/setup_screen.gd")
BASE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "base_classes.json")


def tracked_files():
    out = subprocess.run(["git", "ls-files", "game"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        rel = line[len("game/"):]
        if rel.endswith(EXTS) and not rel.startswith(SKIP_DIRS) and rel not in SKIP_FILES:
            yield rel


def patcher_consts():
    src = open(os.path.join(GAME, "scripts/core/patcher.gd"), encoding="utf-8").read()
    get = lambda k: re.search(r"const %s := (\S+)" % k, src).group(1).strip('"')
    return int(get("BASE_CODE")), get("BASE_NAME"), int(get("BASE_REV"))


def class_names(files):
    names = {}
    for rel in files:
        if rel.endswith(".gd"):
            m = re.search(r"^class_name\s+(\w+)", open(os.path.join(GAME, rel), encoding="utf-8").read(), re.M)
            if m:
                names[m.group(1)] = rel
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="output folder for patch.zip and patch.json")
    ap.add_argument("--url", required=True, help="download folder of the release (patch.zip is appended)")
    ap.add_argument("--new-base", action="store_true", help="this release ships a new APK: record its classes")
    a = ap.parse_args()

    code, name, rev = patcher_consts()
    files = sorted(tracked_files())
    classes = class_names(files)
    if a.new_base or not os.path.exists(BASE_FILE):
        json.dump({"base_rev": rev, "classes": sorted(classes)}, open(BASE_FILE, "w"), indent=1)
    base = json.load(open(BASE_FILE))
    if base["base_rev"] != rev:
        sys.exit("BASE_REV is %d but base_classes.json is for %d: run with --new-base" % (rev, base["base_rev"]))
    new = sorted(set(classes) - set(base["classes"]))
    if new:
        sys.exit("New class_name %s: needs a new APK (raise BASE_REV, then --new-base)" % ", ".join(new))

    os.makedirs(a.out, exist_ok=True)
    zpath = os.path.join(a.out, "patch.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in files:
            z.write(os.path.join(GAME, rel), rel)
            z.writestr(rel + ".remap", '[remap]\n\npath="res://%s"\n' % rel)
    data = open(zpath, "rb").read()
    manifest = {"code": code, "name": name, "needs_base_rev": rev, "url": a.url.rstrip("/") + "/patch.zip",
                "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "files": len(files)}
    json.dump(manifest, open(os.path.join(a.out, "patch.json"), "w"), indent=1)
    print("patch %s (code %d, base rev %d): %d files, %.1f KB" % (name, code, rev, len(files), len(data) / 1024))


if __name__ == "__main__":
    main()
