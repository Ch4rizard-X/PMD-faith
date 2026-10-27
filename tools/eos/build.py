#!/usr/bin/env python3
"""Explorers of Sky / Explorers Remixed area: one entry point.

  python3 -I tools/eos/build.py

1. extraction (vanilla EoS and Remixed ROMs, extracted by tools/fetch.py into WORK_DIR/eos and WORK_DIR/remix)
   -> WORK_DIR/tmp/eos/{strings_e.json, eos_dungeons.json, eos_fixed.json, tilesets_eos.json, tiles/}
   -> WORK_DIR/tmp/eos_remix/{strings_e.json, items_all.json, abilities.json, remix_data.json, eos_dungeons.json,
                              text_e.str, item_p.bin, item_s_p.bin, mappa_s.bin, monster.md}
2. stage 2 on the stage-1 files in game/data (run after the base-data step):
   gen_eos_items      items.json     + 1053 EoS / Remixed items (exclusives, TMs, boxes ...)
   convert_remix      dungeons.json  EoS dungeons with Remixed's floors / spawn / item / trap lists
                      species.json   Remixed abilities for the Pokemon Red doesn't have
   gen_extra_spread   dungeons.json  the remaining non-Red Pokemon spread over fitting floors
                                     (needs growth.json, evo.json from the data step)
   gen_megas_dx       species.json   Rescue Team DX Megas / Primals and real Mega abilities (PokeAPI)
   fixed_rooms        eos_fixed.json the boss rooms the EoS dungeons use
3. move animations -> WORK_DIR/tmp/eos/moveanim/ (sheets, moves.json, moves_data.json, learnsets.json)
   -> game/assets/fx/fx_NNNN.png, game/data/fx.json, game/data/move_fx.json
"""
import os
import runpy
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
for d in (HERE, os.path.join(TOOLS, 'data'), os.path.join(TOOLS, 'fx'), TOOLS):
    if d not in sys.path:
        sys.path.insert(0, d)

import common  # noqa: E402
from paths import need_roms  # noqa: E402


def step(name, fn):
    t = time.time()
    print(f'== {name}', flush=True)
    fn()
    print(f'   ({time.time() - t:.1f}s)', flush=True)


def need_data(*names):
    for n in names:
        common.need(os.path.join(common.DATA, n), f'game/data/{n} (made by an earlier build step)')


def main():
    need_roms()
    common.need(common.POKEAPI_CSV, 'PokeAPI CSV data (run tools/fetch.py)')
    need_data('dungeons.json', 'items.json', 'species.json', 'moves.json')
    import extract, tilesets, convert_dungeons, fixed_rooms  # noqa: E401
    import gen_eos_items, convert_remix, gen_extra_spread, gen_megas_dx  # noqa: E401
    import export_fx, build_game  # noqa: E401

    # 1. extraction
    step('extract strings / items / abilities', extract.main)
    step('EoS tilesets', tilesets.main)
    step('vanilla EoS dungeons (intermediate)', convert_dungeons.main)
    fixed = fixed_rooms.Fixed()
    step('EoS fixed rooms (intermediate)', lambda: fixed_rooms.raw(fixed))

    # 2. stage 2
    step('gen_eos_items', gen_eos_items.main)
    step('convert_remix', convert_remix.main)
    need_data('growth.json', 'evo.json')
    step('gen_extra_spread', gen_extra_spread.main)
    step('gen_megas_dx (species)', gen_megas_dx.main)
    step('data/eos_fixed.json', lambda: fixed_rooms.game(common.load_json(os.path.join(common.DATA, 'dungeons.json')), fixed))

    # 3. move animations
    step('effect sheets', export_fx.main)
    step('move data / learnsets', lambda: runpy.run_path(os.path.join(TOOLS, 'fx', 'build_data.py'), run_name='__main__'))
    step('move animations', lambda: runpy.run_path(os.path.join(TOOLS, 'fx', 'build_moves.py'), run_name='__main__'))
    step('assets/fx, fx.json, move_fx.json', build_game.main)
    import fix_move_classes
    step('move classes', fix_move_classes.main)
    print('eos build done')


if __name__ == '__main__':
    main()
