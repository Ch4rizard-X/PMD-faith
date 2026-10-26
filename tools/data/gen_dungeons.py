#!/usr/bin/env python3
"""Export every Red Rescue Team dungeon (floor properties, Pokemon/item/trap tables) to data/dungeons.json."""
import json, re, os
D = '/tmp/claude-0/pmdred'
G = '/tmp/claude-0/pmd1/game/data'
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
J = lambda p: json.load(open(p))

def consts(path, prefix):
    out = {}
    for m in re.finditer(r'#define (' + prefix + r'\w+)\s+(0x[0-9A-Fa-f]+|\d+)', open(path).read()):
        out.setdefault(m.group(1), int(m.group(2), 0))
    return out
def names_from_s(path, prefix):
    s = open(path, encoding='utf8', errors='replace').read()
    out = {}
    for m in re.finditer(r'\n(' + prefix + r'\w+):\s*\n\.string "([^"\\]*)', s):
        v = m.group(2)
        out[m.group(1)] = 'Poke' if v == '{POKE}' else re.sub(r'\{[^}]*\}', '', v).strip()
    return out

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
mi = open(D + '/data/dungeon/main_data.inc').read()
recs = []
for d in re.findall(r'#include "(\w+)/main_data.inc"', mi):
    raw = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', open(f'{D}/data/dungeon/{d}/main_data.inc').read())]
    recs += [raw[i:i + 28] for i in range(0, len(raw) - 27, 28)]
raw = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', mi[mi.rfind('#include'):])]
recs += [raw[i:i + 28] for i in range(0, len(raw) - 27, 28)]
pf_inc = open(D + '/data/dungeon/pokemon_found.inc').read()
labels = re.findall(r'\.4byte (\w+)', pf_inc[pf_inc.index('DungeonPokemonFoundTable'):])
by_label = {}
for d in os.listdir(D + '/data/dungeon'):
    f = f'{D}/data/dungeon/{d}/pokemon_found.json'
    if os.path.exists(f):
        for t in J(f)['tables']:
            by_label[t['name']] = [[mon_key(p['species']) or p['species'], p['level'], p['probability']] for p in t['pokemon'] if p['probability'] > 0]
ptables = [by_label.get(l, []) for l in labels]
order = re.findall(r'#include "(\w+)/floor_id.inc"', open(D + '/data/dungeon/floor_id.inc').read())
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

# ---- spread the extra Pokemon (not in Red) through dungeons whose Pokemon share their types, at levels fitting their evolution stage
evo = J(G + '/evo.json')
pre_of, evo_lv = {}, {}
for a, lst in evo.items():
    for e in lst:
        pre_of[e[0]] = a
        evo_lv[(a, e[0])] = e[1] if isinstance(e[1], int) and e[1] > 0 else None
def stage_range(k):
    lo = 1
    p = pre_of.get(k)
    if p:
        lv = evo_lv.get((p, k)) or 25
        lo = lv
        if pre_of.get(p): lo = max(lo, 30)
    nxt = [e for e in evo.get(k, [])]
    hi = 100
    if nxt:
        lvs = [e[1] for e in nxt if isinstance(e[1], int) and e[1] > 0]
        hi = (min(lvs) if lvs else 35) + 12
    return lo, hi
SKIP = re.compile(r'^(D\d+|Boss\d+|Autopilot|DojoRegistration)$')
extras = [k for k, v in species.items() if not v.get('red') and not v.get('megaBase') and not v.get('legend') and len(k) == 4 and k in J(G + '/sprites.json')]
cands = []   # (dungeon, floor index, avg level, type profile)
for key, dd in out.items():
    if SKIP.match(dd['dir']): continue
    for fi, fl in enumerate(dd['floors']):
        if not fl['pk']: continue
        prof = {}
        for sp, lv, w in fl['pk']:
            for t in species.get(str(sp), {}).get('types', []): prof[t] = prof.get(t, 0) + w
        lvs = sorted(int(x[1]) for x in fl['pk'])
        cands.append((key, fi, lvs[len(lvs) // 2], prof))
placed = {}
for k in extras:
    lo, hi = stage_range(k)
    ty = species[k]['types']
    scored = {}
    for key, fi, lv, prof in cands:
        if not (lo - 3 <= lv <= hi): continue
        sc = sum(prof.get(t, 0) for t in ty)
        if sc <= 0: continue
        scored.setdefault(key, []).append((sc, fi, lv))
    best = sorted(scored.items(), key=lambda kv: -max(x[0] for x in kv[1]))[:3]
    for key, fl in best:
        for sc, fi, lv in fl:
            placed.setdefault((key, fi), []).append((k, lv, sc))
added = 0
for (key, fi), lst in placed.items():
    lst = sorted(lst, key=lambda x: -x[2])[:6]          # at most 6 extra species per floor, the best type fits
    fl = out[key]['floors'][fi]
    tot = sum(int(x[2]) for x in fl['pk']) or 10000
    share = min(int(tot * 0.25), 1200 * len(lst))      # extras take at most a quarter of the spawns
    w = max(1, share // len(lst))
    for k, lv, _sc in lst:
        fl['pk'].append([k, lv, w, 1]); added += 1
print('extras placed', len({fe[0] for d in out.values() for f in d['floors'] for fe in f['pk'] if len(fe) > 3}), 'of', len(extras), 'entries', added)
json.dump({'dungeons': out, 'item_tables': item_tables, 'trap_tables': trap_tables}, open(G + '/dungeons.json', 'w'), separators=(',', ':'))
print(len(out), 'dungeons;', len(item_tables), 'item tables;', len(trap_tables), 'trap tables')
for k in ['tiny_woods', 'thunderwave_cave', 'western_cave', 'uproar_forest']:
    v = out[k]; print(k, v['name'], len(v['floors']), v['floors'][0]['pk'][:6])
miss = {str(p[0]) for d in out.values() for f in d['floors'] for p in f['pk'] if not str(p[0]).isdigit()}
print('unmapped mons', sorted(miss)[:20])
