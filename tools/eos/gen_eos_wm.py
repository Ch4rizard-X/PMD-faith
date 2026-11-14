#!/usr/bin/env python3
"""game/data/eos_wm.json: the Explorers of Sky ids a Wonder Mail S password uses, matched to this game's keys.

Source: the user's vanilla Explorers of Sky ROM (extracted by tools/fetch.py): BALANCE/monster.md (EoS monster
index -> national dex) and MESSAGE/text_e.str (via tools/eos/extract.py -> WORK_DIR/tmp/eos/strings_e.json:
monster, item and dungeon names). Wonder Mail S ids are the vanilla game's, so the vanilla ROM is used here even
where the dungeons themselves come from Explorers Remixed.

  {"species": {"<EoS monster index>": "<species key>"},   indices 1..599 (600+ = the same Pokemon, female)
   "items":   {"<EoS item id>": "<item key>"},            matched by name, like gen_eos_items.py
   "dungeons": {"<EoS dungeon id>": "<name>"}}           names, for messages about dungeons this game lacks
Unown's 28 forms (monster.md: national dex 201, in the order A-Z, !, ?) get the form keys of
tools/data/redsrc.unown_key ('0201', '0201UB' .. '0201UZ', '0201UEX', '0201UQU').
"""
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import EOS, T_EOS, rd, common  # noqa: E402

N_ITEMS = 1400
UNOWN = ['0201'] + ['0201U' + chr(c) for c in range(ord('B'), ord('Z') + 1)] + ['0201UEX', '0201UQU']


def _after(S, a, b):
    """Index of the string a that is followed by b (the start of a name table)."""
    for i in range(len(S) - 1):
        if S[i] == a and S[i + 1] == b:
            return i
    raise SystemExit('gen_eos_wm: name table %r/%r not found in text_e.str' % (a, b))


def main():
    S = json.load(open(common.p(os.path.join(T_EOS, 'strings_e.json')), encoding='utf-8'))
    md = rd(EOS, 'fs', 'BALANCE', 'monster.md')
    species = common.load_json(os.path.join(common.DATA, 'species.json'))
    items = common.load_json(os.path.join(common.DATA, 'items.json'))
    mon0 = _after(S, 'Bulbasaur', 'Ivysaur') - 1       # name of monster index i = S[mon0 + i]
    item0 = _after(S, 'Nothing', 'Stick')              # item id i = S[item0 + i]
    dun0 = _after(S, 'Test Dungeon', 'Beach Cave')     # dungeon id i = S[dun0 + i]
    n = struct.unpack_from('<I', md, 4)[0]
    sp = {}
    unown = 0
    for i in range(1, min(n, 600)):
        nat = struct.unpack_from('<H', md, 8 + 68 * i + 4)[0]
        if nat == 0:
            continue
        if nat == 201:
            k = UNOWN[unown] if unown < len(UNOWN) else '0201'
            unown += 1
        else:
            k = '%04d' % nat
        if k in species:
            sp[str(i)] = k
    norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
    by_name = {}
    for k, v in items.items():
        by_name.setdefault(norm(v.get('name', '')), k)
        if v.get('red_cat') == 'tms_hms':
            by_name.setdefault(norm('TM ' + v.get('name', '')), k)
    it = {}
    for i in range(1, N_ITEMS):
        nm = re.sub(r'\[[^\]]*\]', '', S[item0 + i]).strip()
        k = by_name.get(norm(nm)) if nm else None
        if k:
            it[str(i)] = k
    dn = {str(i): S[dun0 + i] for i in range(1, 180) if S[dun0 + i]}
    common.save_json(os.path.join(common.DATA, 'eos_wm.json'), {'species': sp, 'items': it, 'dungeons': dn})
    print('eos_wm.json: %d species, %d items, %d dungeon names (Unown forms %d)' % (len(sp), len(it), len(dn), unown))


if __name__ == '__main__':
    main()
