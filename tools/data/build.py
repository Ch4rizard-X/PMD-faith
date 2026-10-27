#!/usr/bin/env python3
"""Stage 1 of the data build: the base tables in game/data/ from the pret/pmd-red decomp, the user's Red ROM, PokeAPI,
pret/pmd-sky (IQ skill add-ons) and the extracted Explorers of Sky / Remixed ROMs (Remixed numbers for later moves).

  species.json growth.json evo.json moves.json items.json types.json   gen_data.py (+ proto.py, proto_tables.py,
                                                                       proto_items.json, pokeapi.py, redsrc.py)
  dungeons.json (Red's 64 dungeons)                                    gen_dungeons.py
  friend_areas.json                                                    gen_friend_areas.py
  fixed_rooms.json                                                     gen_fixed_rooms.py (needs gcc)
  iq.json                                                              gen_iq.py, gen_iq_sky.py
  quiz.json  missions.json  red_evo.json                               gen_quiz.py, gen_missions.py, gen_red_evo.py
  red_town_text.json  menu_text.json  kecleon_sets.json                extract_text.py, gen_menu_text.py, kec_sets.py
  item_icons.json + assets/ui/items.png                                icons.py
  game/scripts/core/wonder_mail.gd (generated tables)                  gen_wondermail.py
Stage 2 (tools/eos, tools/data/convert_remix.py, gen_eos_items.py, gen_extra_spread.py, gen_megas_dx.py) runs afterwards."""
import os
import runpy
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path[:0] = [TOOLS, HERE]
import common  # noqa: E402

STEPS = ["gen_data", "gen_dungeons", "gen_friend_areas", "gen_fixed_rooms", "gen_iq", "gen_iq_sky", "gen_quiz", "gen_missions",
         "gen_wondermail", "gen_red_evo", "extract_text", "gen_menu_text", "kec_sets", "icons"]


def run(path):
    t = time.time()
    print("--", os.path.relpath(path, TOOLS), flush=True)
    d = os.path.dirname(path)
    sys.path.insert(0, d)
    try:
        runpy.run_path(path, run_name="__main__")
    except SystemExit as e:              # some tools end with sys.exit(0)
        if e.code not in (None, 0):
            raise
    finally:
        sys.path.remove(d)
    print("   %.1f s" % (time.time() - t), flush=True)


def main():
    common.need(common.PMDRED, "pret/pmd-red")
    common.need(common.POKEAPI_CSV, "PokeAPI CSV data")
    # Remixed move numbers (tools/eos/extract.py -> tools/fx/build_data.py); made here if stage 2 has not made them yet
    if not os.path.exists(os.path.join(common.TMP, "eos", "moveanim", "moves_data.json")):
        if not os.path.exists(os.path.join(common.TMP, "eos", "strings_e.json")):
            run(os.path.join(TOOLS, "eos", "extract.py"))
        run(os.path.join(TOOLS, "fx", "build_data.py"))
    for s in STEPS:
        run(os.path.join(HERE, s + ".py"))
    print("data stage 1 done")


if __name__ == "__main__":
    main()
