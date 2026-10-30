#!/usr/bin/env python3
"""Export every Red Rescue Team dungeon (floor properties, Pokemon/item/trap tables) to data/dungeons.json (stage 1).
Sources: pmd-red data/dungeon/* (main_data.inc, pokemon_found, floor_id, dungeon_item_data, trap_data, dungeon_data).
Pokemon not in Red are spread through dungeons whose Pokemon share their types. Stage 2 (tools/eos/convert_dungeons.py,
tools/data/convert_remix.py, gen_extra_spread.py) adds the Explorers of Sky dungeons and more spreading."""
import json, re, os, sys
sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
import proto  # noqa: E402
import redsrc  # noqa: E402
from redsrc import consts as _consts, names_from_s as _names  # noqa: E402
D = common.PMDRED
G = common.DATA
norm = redsrc.norm
J = lambda p: json.load(open(p, encoding='utf-8'))
consts = lambda path, prefix: _consts(os.path.relpath(path, D), prefix)
names_from_s = lambda path, prefix: _names(os.path.relpath(path, D), prefix)

species = J(G + '/species.json'); items = J(G + '/items.json')
sp_by_norm = {'farfetchd': '0083'}
for k, v in species.items():
    if len(k) == 4: sp_by_norm.setdefault(norm(v['name']), k)
it_by_norm = {norm(v['name']): k for k, v in items.items()}; it_by_norm['poke'] = 'poke'

# MONSTER_X -> species key (through Red's monster names)
mon_ids = consts(D + '/include/constants/monster.h', 'MONSTER_')
mon_names = names_from_s(D + '/data/monster/monster_names.s', 'MonsterName')
mdata = J(D + '/data/monster/monster_data.json')
def mon_key(c):
    i = mon_ids.get(c)
    if i is None or i >= len(mdata): return None
    nm = mon_names.get(mdata[i]['name'], '')
    return sp_by_norm.get(norm(nm))
# ITEM_X -> item id
item_ids = consts(D + '/include/constants/item.h', 'ITEM_')
item_names = names_from_s(D + '/data/item/item_names.s', 'ItemName')
idata = J(D + '/data/item/item_data.json')
def item_key(c):
    i = item_ids.get(c)
    if i is None or i >= len(idata): return None
    return it_by_norm.get(norm(item_names.get(idata[i]['name'], '')))

item_tables = []
for t in J(D + '/data/dungeon/dungeon_item_data.json'):
    cats = []
    for c in t['categories']:
        its = [[item_key(x['item']) or x['item'], x['itemProbability']] for x in c['items']]
        cats.append({'cat': c['category'].replace('CATEGORY_', '').lower(), 'p': c['categoryProbability'], 'items': its})
    item_tables.append({'desc': t.get('description', ''), 'cats': cats})
TRAP_ID = {'Trip Trap': 'trip', 'Mud Trap': 'mud', 'Sticky Trap': 'sticky', 'Grimy Trap': 'grimy', 'Summon Trap': 'summon', 'Pitfall Trap': 'pitfall',
           'Warp Trap': 'warp', 'Gust Trap': 'gust', 'Spin Trap': 'spin', 'Slumber Trap': 'slumber', 'Slow Trap': 'slow', 'Seal Trap': 'seal',
           'Poison Trap': 'poison', 'Selfdestruct Trap': 'selfdestruct', 'Explosion Trap': 'explosion', 'PP-Zero Trap': 'ppzero',
           'Chestnut Trap': 'chestnut', 'Wonder Tile': 'wonder', 'Pokemon Trap': 'pokemon', 'Spiked Tile': 'spiked'}
trap_tables = [{TRAP_ID.get(k, k): v for k, v in t['traps'].items() if v} for t in J(D + '/data/dungeon/trap_data.json')]

# ---- global tables: floor records (per-dir files in include order, then the inline block), Pokemon tables
mi = redsrc.read('data/dungeon/main_data.inc')
recs = []
for d in re.findall(r'#include "(\w+)/main_data.inc"', mi):
    raw = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', redsrc.read(f'data/dungeon/{d}/main_data.inc'))]
    recs += [raw[i:i + 28] for i in range(0, len(raw) - 27, 28)]
raw = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', mi[mi.rfind('#include'):])]
recs += [raw[i:i + 28] for i in range(0, len(raw) - 27, 28)]
pf_inc = redsrc.read('data/dungeon/pokemon_found.inc')
labels = re.findall(r'\.4byte (\w+)', pf_inc[pf_inc.index('DungeonPokemonFoundTable'):])
by_label = {}
for d in os.listdir(D + '/data/dungeon'):
    f = f'{D}/data/dungeon/{d}/pokemon_found.json'
    if os.path.exists(f):
        for t in J(f)['tables']:
            by_label[t['name']] = [[mon_key(p['species']) or p['species'], p['level'], p['probability']] for p in t['pokemon'] if p['probability'] > 0]
ptables = [by_label.get(l, []) for l in labels]
order = re.findall(r'#include "(\w+)/floor_id.inc"', redsrc.read('data/dungeon/floor_id.inc'))
dj = J(D + '/data/dungeon/dungeon_data.json')
dname = {}
for n, m in enumerate(dj):
    nm = m['name'].replace('DUNGEON_', '').replace('_', ' ').title().replace('Mt ', 'Mt. ')
    dname[n] = nm
out = {}
for n, d in enumerate(order):
    f = f'{D}/data/dungeon/{d}/floor_id.json'
    if not os.path.exists(f): continue
    floors = []
    for t in J(f)['tables']:
        floors.append({'props': recs[t['MainData']] if t['MainData'] < len(recs) else recs[-1], 'pk': [list(x) for x in ptables[t['Pokemon']]] if t['Pokemon'] < len(ptables) else [],
                       'items': t['Items'], 'traps': t['Traps'], 'shop': t['KecleonShop'], 'house_items': t['MonsterRoomItems'], 'buried': t['BuriedItems']})
    meta = dj[n] if n < len(dj) else {}
    key = re.sub(r'(?<!^)(?=[A-Z])', '_', d).lower()
    out[key] = {'dir': d, 'name': dname.get(n, d), 'index': n, 'floors': floors, 'up': meta.get('stairDirectionUp', False),
                'recruit': meta.get('recruitingEnabled', True), 'max_items': meta.get('maxItemsAllowed', 20),
                'party': meta.get('maxPartyMembers', 4), 'turn_limit': meta.get('turnLimit', 1000)}

# ---- spread the Pokemon Red doesn't have through Red's dungeons (gen_extra_spread.py: type, strength and level fit;
# legendaries / Ultra Beasts / Paradox Pokemon rare and deep in late-game dungeons). The eos step spreads again over
# Red's and Explorers of Sky's dungeons together.
import gen_extra_spread  # noqa: E402
evo = J(G + '/evo.json')
gr = J(G + '/growth.json')
HAS_SPRITE = set(proto.build_all()['DEX'])   # species with a SpriteCollab sprite (data/sprites.json is made later)
gen_extra_spread.apply({'dungeons': out}, species, HAS_SPRITE, gr['mon'], evo, curve=gr['curve'])
with open(common.p(G, 'dungeons.json'), 'w') as f:
    json.dump({'dungeons': out, 'item_tables': item_tables, 'trap_tables': trap_tables}, f, separators=(',', ':'))
print(len(out), 'dungeons;', len(item_tables), 'item tables;', len(trap_tables), 'trap tables')
for k in ['tiny_woods', 'thunderwave_cave', 'western_cave', 'uproar_forest']:
    v = out[k]; print(k, v['name'], len(v['floors']), v['floors'][0]['pk'][:6])
miss = {str(p[0]) for d in out.values() for f in d['floors'] for p in f['pk'] if not str(p[0]).isdigit()}
print('unmapped mons', sorted(miss)[:20])
