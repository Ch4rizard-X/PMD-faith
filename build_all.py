"""Build everything the game needs from your own ROMs and public resources.

  1. Copy build_config.example.json to build_config.json and fill in your three ROM paths.
  2. python build_all.py              (or: python build_all.py --from sprites   to resume at a step)
  3. Open game/project.godot in Godot 4.7.2.

Steps (each can be run on its own as python tools/<area>/build.py):
  fetch     download pret/pmd-red, pret/pmd-sky, SpriteCollab, PokeAPI, SkyTemple's script data; extract the ROMs
  data      base tables from the decomp + PokeAPI (species, moves, items, dungeons, IQ, quiz, jobs, text)
  eos       Explorers of Sky / Remixed content on top (dungeons, items, abilities, Megas) + move animations
  sprites   Pokémon sprites, portraits and shiny colours from SpriteCollab
  dungeon   dungeon tilesets and dungeon graphics from the ROMs
  ground    story maps, town, UI graphics, world maps, music and sound effects
"""
import argparse
import os
import runpy
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
STEPS = [
    ("fetch", "tools/fetch.py"),
    ("data", "tools/data/build.py"),
    ("eos", "tools/eos/build.py"),
    ("sprites", "tools/sprites/build.py"),
    ("dungeon", "tools/dungeon/build.py"),
    ("ground", "tools/ground/build.py"),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="start", choices=[s for s, _ in STEPS], help="start at this step")
    ap.add_argument("--only", choices=[s for s, _ in STEPS], help="run just this step")
    a = ap.parse_args()
    if not os.path.exists(os.path.join(ROOT, "build_config.json")) and not os.environ.get("RED_ROM"):
        sys.exit("Copy build_config.example.json to build_config.json and set your ROM paths first.")
    names = [s for s, _ in STEPS]
    todo = STEPS
    if a.only:
        todo = [s for s in STEPS if s[0] == a.only]
    elif a.start:
        todo = STEPS[names.index(a.start):]
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    for name, script in todo:
        t0 = time.time()
        print(f"\n=== {name} ({script}) ===", flush=True)
        path = os.path.join(ROOT, script)
        sys.path.insert(0, os.path.dirname(path))
        runpy.run_path(path, run_name="__main__")
        sys.path.pop(0)
        print(f"=== {name}: done in {time.time() - t0:.0f} s", flush=True)
    print("\nAll done. Open game/project.godot in Godot 4.7.2.")


if __name__ == "__main__":
    main()
