"""Build everything the game needs from your own ROMs and public resources.

  1. Copy build_config.example.json to build_config.json and fill in your three ROM paths
     (on Windows, SETUP_STEP2_build_game_files.bat does this for you).
  2. python build_all.py
  3. Open game/project.godot in Godot 4.7.2.

If the build stops, fix the problem and run it again: finished steps are skipped and it continues where it
stopped. python build_all.py --fresh starts over; --from STEP / --only STEP run particular steps.
Everything printed is also saved to build_work/build_log.txt.

Steps (each can be run on its own as python tools/<area>/build.py):
  fetch     download pret/pmd-red, pret/pmd-sky, SpriteCollab, PokeAPI, SkyTemple's script data; check and extract the ROMs
  data      base tables from the decomp + PokeAPI (species, moves, items, dungeons, IQ, quiz, jobs, text)
  eos       Explorers of Sky / Remixed content on top (dungeons, items, abilities, Megas) + move animations
  sprites   Pokémon sprites, portraits and shiny colours from SpriteCollab
  dungeon   dungeon tilesets and dungeon graphics from the ROMs
  ground    story maps, town, UI graphics, world maps, music and sound effects
"""
import argparse
import json
import os
import runpy
import sys
import time
import traceback

ROOT = os.path.dirname(os.path.abspath(__file__))
STEPS = [
    ("fetch", "tools/fetch.py", "downloading resources and reading your ROMs"),
    ("data", "tools/data/build.py", "building the game data"),
    ("eos", "tools/eos/build.py", "adding the Explorers of Sky content and move animations"),
    ("sprites", "tools/sprites/build.py", "packing the Pokémon sprites and portraits (slow)"),
    ("dungeon", "tools/dungeon/build.py", "building the dungeon graphics"),
    ("ground", "tools/ground/build.py", "building maps, menus, music and sound effects (slowest)"),
]


class Tee:
    """Print to the screen and to the log file at the same time."""
    def __init__(self, stream, log):
        self.stream, self.log = stream, log

    def write(self, s):
        self.stream.write(s)
        self.log.write(s)

    def flush(self):
        self.stream.flush()
        self.log.flush()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    names = [s[0] for s in STEPS]
    ap.add_argument("--from", dest="start", choices=names, help="start at this step")
    ap.add_argument("--only", choices=names, help="run just this step")
    ap.add_argument("--fresh", action="store_true", help="redo every step, even finished ones")
    a = ap.parse_args()
    if not os.path.exists(os.path.join(ROOT, "build_config.json")) and not os.environ.get("RED_ROM"):
        sys.exit("No build_config.json yet.\n"
                 "Windows: double-click SETUP_STEP2_build_game_files.bat, it asks for your ROM files.\n"
                 "Otherwise: copy build_config.example.json to build_config.json and set your three ROM paths.")
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import common                                   # noqa: E402  (creates the work folder)
    log_path = os.path.join(common.WORK, "build_log.txt")
    progress_path = os.path.join(common.WORK, "progress.json")
    log = open(log_path, "a", encoding="utf-8")
    sys.stdout = Tee(sys.stdout, log)
    sys.stderr = Tee(sys.stderr, log)
    print(f"\n===== build started {time.strftime('%Y-%m-%d %H:%M')} =====")

    done = []
    if os.path.exists(progress_path) and not a.fresh:
        try:
            done = json.load(open(progress_path, encoding="utf-8"))
        except ValueError:
            done = []
    todo = STEPS
    if a.only:
        todo = [s for s in STEPS if s[0] == a.only]
        done = [d for d in done if d != a.only]
    elif a.start:
        todo = STEPS[names.index(a.start):]
        done = [d for d in done if d not in names[names.index(a.start):]]

    for name, script, what in todo:
        n = names.index(name) + 1
        if name == "eos" and common.RED_ONLY:
            print(f"\n[{n}/{len(STEPS)}] {name}: skipped (Red Rescue Team only, no Explorers of Sky ROMs)", flush=True)
            continue
        if name in done and name != "fetch":       # fetch always runs: instant when complete, repairs a stopped download
            print(f"\n[{n}/{len(STEPS)}] {name}: already done, skipping (python build_all.py --fresh redoes everything)")
            continue
        t0 = time.time()
        print(f"\n[{n}/{len(STEPS)}] {name}: {what} ...", flush=True)
        path = os.path.join(ROOT, script)
        sys.path.insert(0, os.path.dirname(path))
        try:
            runpy.run_path(path, run_name="__main__")
        except SystemExit as e:
            if e.code not in (None, 0):
                stop(name, e.code if isinstance(e.code, str) else "", log_path)
        except Exception:
            traceback.print_exc()
            stop(name, "", log_path)
        finally:
            sys.path.pop(0)
        done = [d for d in done if d != name] + [name]
        json.dump(done, open(progress_path, "w", encoding="utf-8"))
        print(f"[{n}/{len(STEPS)}] {name}: done in {(time.time() - t0) / 60:.1f} min", flush=True)
    print("\nAll done! The game files are in game/assets and game/data.\n"
          "Next: open game/project.godot in Godot 4.7.2 and press Play (see SETUP.md, part 4).")


def stop(step, msg, log_path):
    print(f"\n*** The build stopped during the '{step}' step. ***")
    if msg:
        print(msg)
    print("\nWhat to do:\n"
          "  - Read the message just above. Most problems are a wrong ROM file or a missing program\n"
          "    (see SETUP.md, Troubleshooting).\n"
          "  - Fix it and start the build again. Finished steps are skipped, so it continues from here.\n"
          f"  - Everything the build printed is saved in {log_path}, if you need to ask for help.")
    sys.exit(1)


if __name__ == "__main__":
    main()
