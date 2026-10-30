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
import shutil
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
    if not common.RED_ONLY and not os.path.exists(os.path.join(common.TMP, "eos", "moveanim", "moves_data.json")):
        if not os.path.exists(os.path.join(common.TMP, "eos", "strings_e.json")):
            run(os.path.join(TOOLS, "eos", "extract.py"))
        run(os.path.join(TOOLS, "fx", "build_data.py"))
    red_dir = os.path.join(common.DATA, "red")
    for s in STEPS:
        if s == "gen_iq_sky" and not common.RED_ONLY:     # Red's own IQ skills, before Explorers of Sky's are added
            shutil.copy(os.path.join(common.DATA, "iq.json"), os.path.join(red_dir, "iq.json"))
        if common.RED_ONLY and s == "gen_iq_sky":        # Explorers of Sky's IQ skills (its text)
            continue
        run(os.path.join(HERE, s + ".py"))
    # Rescue Team DX's Mega Evolutions, the Empowerment Seed and the remake's Exp. Share in every build (the launcher's Mega Evolution switch
    # turns them on or off); the old prototype's unused Mega Stone item goes
    run(os.path.join(HERE, "gen_megas_dx.py"))
    import gen_eos_items
    items_path = os.path.join(common.DATA, "items.json")
    items = common.load_json(items_path)
    items.pop("megastone", None)
    if "empowerseed" in items:
        items["empowerseed"].update(gen_eos_items.EMPOWER_SEED)
    items.setdefault("expshare", dict(gen_eos_items.EXP_SHARE))     # the remake's Exp. Share (Game page: Remake items)
    common.save_json(items_path, items)
    # status moves Red's data gives a damage category (also in Red-only builds, which have no eos step)
    import fix_move_classes
    fix_move_classes.main()
    fix_move_classes.main(os.path.join(red_dir, "moves.json"))
    # The launcher's Game page (each part of a full build Red's own or Explorers of Sky's): the tables as a Red-only
    # build has them, before the Explorers of Sky step changes them (data/red/, laid over the full ones by the game).
    if common.RED_ONLY:
        if os.path.isdir(red_dir):
            shutil.rmtree(red_dir)
    else:
        for n in ("species.json", "items.json", "dungeons.json"):
            shutil.copy(os.path.join(common.DATA, n), os.path.join(red_dir, n))
    common.save_json(os.path.join(common.DATA, "build_info.json"), {"red_only": bool(common.RED_ONLY)})
    print("data stage 1 done")


if __name__ == "__main__":
    main()
