#!/usr/bin/env python3
"""Rebuild everything of the "dungeon graphics" area from the ROMs (no arguments, idempotent):
  assets/tiles/* + data/tilesets.json                      (gen_tilesets.py: Red + Explorers of Sky tilesets)
  assets/dungeon/* + data/dungeon_gfx.json + dungeon_talk.json  (gen_dungeon_gfx.py: Red ROM dungeon graphics)
Run from anywhere:  python3 -I tools/dungeon/build.py"""
import os, sys, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import common
import gen_tilesets, gen_dungeon_gfx


def main():
    for sub in ('tiles', 'dungeon'):        # from scratch: drop old outputs (keep Godot's .import files)
        d = os.path.join(common.ASSETS, sub)
        if os.path.isdir(d):
            for f in os.listdir(d):
                if not f.endswith('.import') and os.path.isfile(os.path.join(d, f)):
                    os.remove(os.path.join(d, f))
    gen_tilesets.main()
    gen_dungeon_gfx.main()
    print('dungeon graphics: done')


if __name__ == '__main__':
    main()
