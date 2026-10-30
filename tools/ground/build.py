#!/usr/bin/env python3
"""Build everything of the "ground" area from the decomp / ROM extracts in WORK_DIR (see tools/common.py):

  assets/ground/*  data/ground/*  data/red_credits.json   ground maps, scripts, ornaments, credits
  assets/town/*    data/town.json                          the walkable town
  assets/worldmap/* data/world_map.json                    Red + Explorers of Sky world maps
  assets/ui/*  (not mark_*.png / items.png)               UI graphics + pmd_red_text.ttf
  assets/music/*  data/eos_loops.json                      Red (m4a) + Explorers of Sky (DSE) music
  assets/sfx/*                                             Red sound effects (m4a)

usage: python3 -I tools/ground/build.py [--skip-audio] [--only step,step]
steps: ground_bg ground_assets scripts extra ornaments anim_offsets credits front ui worldmap town eos_music red_music sfx
Needs data/dungeons.json and data/friend_areas.json from tools/data (for the world map keys).
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import common  # noqa: E402

PY = [sys.executable, "-I", "-X", "utf8"]           # -I ignores PYTHONUTF8; -X utf8 still applies (Windows: UTF-8 files, not cp1252)
UI_OTHERS = ("mark_", "items.png")           # files in assets/ui other workers own


def T(*p):
    return os.path.join(TOOLS, *p)


STEPS = [
    ("ground_bg", [T("ground", "gen_ground_bg.py")]),
    ("ground_assets", [T("ground", "gen_ground_assets.py")]),
    ("scripts", [T("ground", "gen_ground_scripts.py")]),
    ("extra", [T("ground", "gen_ground_extra.py")]),
    ("ornaments", [T("ground", "gen_ornaments.py")]),
    ("red_moves", [T("fx", "red_moves.py")]),
    ("anim_offsets", [T("ground", "gen_red_anim_offsets.py")]),
    ("credits", [T("ground", "gen_credits.py")]),
    ("front", [T("ground", "gen_front_assets.py")]),
    ("ui", [T("ground", "gen_ui.py")]),
    ("worldmap", [T("data", "gen_world_map.py")]),
    ("town", [T("data", "gen_town.py")]),
    ("eos_music", [T("music", "eos", "make.py")]),
    ("red_music", [T("music", "red", "make.py"), "bgm"]),
    ("sfx", [T("music", "sfx.py")]),
]
AUDIO = {"eos_music", "red_music", "sfx"}


def clean(steps):
    """Remove the outputs of the steps about to run, so the build is from scratch."""
    A, D = common.ASSETS, common.DATA
    rm = []
    if "ground_bg" in steps:
        rm.append(os.path.join(common.TMP, "ground_bg"))
    if "ground_assets" in steps:
        rm += [p for p in glob.glob(os.path.join(A, "ground", "*")) if os.path.basename(p) not in ("orn", "credits")]
    if "scripts" in steps or "extra" in steps:
        rm.append(os.path.join(D, "ground"))
    if "ornaments" in steps:
        rm.append(os.path.join(A, "ground", "orn"))
    if "red_moves" in steps:
        rm += [os.path.join(A, "fx_red"), os.path.join(D, "red_move_fx.json")]
    if "credits" in steps:
        rm += [os.path.join(A, "ground", "credits"), os.path.join(D, "red_credits.json")]
    if "front" in steps:
        rm.append(os.path.join(A, "ui", "front"))
    if "ui" in steps:
        rm += [p for p in glob.glob(os.path.join(A, "ui", "*"))
               if os.path.isfile(p) and not os.path.basename(p).startswith(UI_OTHERS)]
    if "worldmap" in steps:
        rm += [os.path.join(A, "worldmap"), os.path.join(D, "world_map.json")]
    if "town" in steps:
        rm += [os.path.join(A, "town"), os.path.join(D, "town.json")]
    if "eos_music" in steps:
        rm += glob.glob(os.path.join(A, "music", "eos_*")) + [os.path.join(D, "eos_loops.json"),
                                                               os.path.join(common.TMP, "eos_bgm_cache", "_stats.json")]
    if "red_music" in steps:
        rm += [p for p in glob.glob(os.path.join(A, "music", "*")) if not os.path.basename(p).startswith("eos_")]
        rm.append(os.path.join(common.TMP, "red_music_stats.json"))
    if "sfx" in steps:
        rm.append(os.path.join(A, "sfx"))
    for p in rm:
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.remove(p)


def merge_red_loops():
    """Add Red's loop points as "red_NNN" entries to data/eos_loops.json (audio.gd reads only the EoS keys today)."""
    stats = os.path.join(common.TMP, "red_music_stats.json")
    path = os.path.join(common.DATA, "eos_loops.json")
    if not (os.path.exists(stats) and os.path.exists(path)):
        return
    loops = common.load_json(path)
    loops = {k: v for k, v in loops.items() if not k.startswith("red_")}
    for k, v in sorted(common.load_json(stats).items()):
        loops["red_" + k] = v
    common.save_json(path, loops, pretty=True)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    names = [s for s, _ in STEPS]
    if "--only" in argv:
        want = argv[argv.index("--only") + 1].split(",")
        bad = [w for w in want if w not in names]
        if bad:
            sys.exit("unknown step(s): %s" % bad)
    else:
        want = names
    if common.RED_ONLY:
        want = [w for w in want if w != "eos_music"]
    if "--skip-audio" in argv:
        want = [w for w in want if w not in AUDIO]
    common.need(os.path.join(common.PMDRED, "baserom.gba"), "pmd-red decomp with your Red ROM (tools/fetch.py)")
    clean(set(want))
    failed = []
    for name, cmd in STEPS:
        if name not in want:
            continue
        t0 = time.time()
        print("== %s" % name, flush=True)
        # the part's output goes through this process's stdout, so build_all's log (and the setup screen) gets it
        r = subprocess.Popen(PY + cmd, cwd=common.ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace")
        for ln in r.stdout:
            print("   " + ln.rstrip(), flush=True)
        r.wait()
        print("== %s %s (%.0fs)" % (name, "ok" if r.returncode == 0 else "FAILED", time.time() - t0), flush=True)
        if r.returncode:
            failed.append(name)
    if "red_music" in want or "eos_music" in want:
        merge_red_loops()
    if failed:
        sys.exit("failed steps: " + ", ".join(failed))
    print("ground build done")


if __name__ == "__main__":
    main()
