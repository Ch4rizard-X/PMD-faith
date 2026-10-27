#!/usr/bin/env python3
"""Stage 2: Explorers Remixed content for game/data/dungeons.json and game/data/species.json.

Dungeons: every Explorers of Sky dungeon gets Explorers Remixed's floors, spawn lists, item lists and trap lists
(Remixed's mappa_s.bin / arm9 dungeon table, read with tools/eos/convert_dungeons.py; music ids from the vanilla
overlay 10 table). The Red dungeons and the item/trap tables they use are kept; the EoS tables are rebuilt.
  - a dungeon that is already in dungeons.json keeps its "index" and "level_reset";
  - otherwise a dungeon of vanilla EoS is numbered after the Red ones in vanilla order, with level_reset from its
    restriction flags (bit 4); a Remixed-only dungeon (Deep Concealed Ruins) gets index = highest index + 1 + its EoS id.
  The Remixed conversion is also written to WORK_DIR/tmp/eos_remix/eos_dungeons.json.
Species: Pokemon that are not in Red (and not Mega forms) take the abilities Explorers Remixed gives them
(monster.md of Remixed, first entry of the national dex number; ability names slugged like PokeAPI's).
Needs items.json after gen_eos_items.py (exclusive items appear in Remixed's item lists).
"""
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'eos'))
import convert_dungeons as CD  # noqa: E402
from paths import EOS, REMIX, T_EOS, T_RX, common, rd  # noqa: E402

def save_ascii(path, obj):
    """Compact JSON with non-ASCII escaped (the format the game's species/dungeons files have always had)."""
    with open(common.p(path), 'w', encoding='utf-8') as f:
        json.dump(obj, f, separators=(',', ':'))


CATNAME_RX = {**CD.CATNAME, 15: 'exclusive'}
slug = lambda n: re.sub(r'[^a-z0-9]+', '-', n.lower()).strip('-')


def remix_dungeons(db, items, species):
    S = common.load_json(os.path.join(T_RX, 'strings_e.json'))
    base = dict(CD.red_part(db), dungeons=db['dungeons'])     # numbering continues after every current dungeon
    return CD.from_rom(REMIX, S, base, items, species, CATNAME_RX, ov10_base=EOS)


def vanilla_keys():
    """Keys of the dungeons vanilla EoS has, in order (tools/eos/convert_dungeons.py's vanilla conversion)."""
    return list(common.load_json(os.path.join(T_EOS, 'eos_dungeons.json'))['dungeons'])


def merge_dungeons(db, R):
    arm9 = rd(REMIX, 'arm9.bin')
    old = db['dungeons']
    red = CD.red_part(db)
    out = dict(red['dungeons'])
    top = max(int(v.get('index', 0)) for v in red['dungeons'].values())
    vk = [k for k in vanilla_keys() if k in R['dungeons']]
    vindex = {k: top + 1 + i for i, k in enumerate(vk)}
    top = max([top] + [int(v['index']) for k, v in old.items() if k.startswith('eos_')] + list(vindex.values()))
    for k, d in R['dungeons'].items():
        d = dict(d)
        flags = struct.unpack_from('<I', arm9, 0xA0C64 + 12 * d['eos_id'])[0]
        if k in old:
            d['index'] = old[k]['index']
            if 'level_reset' in old[k]:
                d['level_reset'] = old[k]['level_reset']
        elif k in vindex:
            d['index'] = vindex[k]
            d['level_reset'] = bool(flags & 16)
        else:
            d['index'] = top + 1 + d['eos_id']
        out[k] = d
    return {'dungeons': out, 'item_tables': R['item_tables'], 'trap_tables': R['trap_tables']}


def apply_abilities(species):
    R = common.load_json(os.path.join(T_RX, 'remix_data.json'))
    A = R['abilities']
    first = {}
    for m in R['mons']:
        first.setdefault(m[1], m)
    n = 0
    for k, v in species.items():
        if v.get('red') or v.get('megaBase') or len(k) != 4:
            continue
        m = first.get(int(k))
        if not m:
            continue
        ab = [slug(A[str(x)][0]) for x in (m[2], m[3]) if x and str(x) in A]
        if ab:
            if v.get('ab') != ab:
                n += 1
            v['ab'] = ab
    return species, n


def main():
    G = common.DATA
    db = common.load_json(f'{G}/dungeons.json')
    items = common.load_json(f'{G}/items.json')
    species = common.load_json(f'{G}/species.json')
    R = remix_dungeons(db, items, species)
    with open(common.p(os.path.join(T_RX, 'eos_dungeons.json')), 'w') as f:
        json.dump(R, f)
    new = merge_dungeons(db, R)
    save_ascii(f'{G}/dungeons.json', new)
    species, n = apply_abilities(species)
    save_ascii(f'{G}/species.json', species)
    print('convert_remix: %d EoS dungeons (Remixed lists), %d item tables, %d trap tables; %d species got Remixed abilities'
          % (len(R['dungeons']), len(new['item_tables']), len(new['trap_tables']), n))


if __name__ == '__main__':
    main()
