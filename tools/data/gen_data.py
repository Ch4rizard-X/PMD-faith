#!/usr/bin/env python3
"""Build the Godot game's data files.
Red Rescue Team tables (pmd-red decomp) are the source of truth for every Pokemon, move and
item that exists in Red. Pokemon after #386 come from the old remake's tables, converted to
Red's format the same way the remake did."""
import json, re, os
D = '/tmp/claude-0/pmdred'
R = '/tmp/claude-0/pmd1/dump'
OUT = '/tmp/claude-0/pmd1/game/data'
os.makedirs(OUT, exist_ok=True)
J = lambda p: json.load(open(p))

def names_from_s(path, prefix):
    s = open(path, encoding='utf8', errors='replace').read()
    out = {}
    for m in re.finditer(r'\n(' + prefix + r'\w+):\s*\n\.string "([^"\\]*)', s):
        v = m.group(2)
        out[m.group(1)] = 'Poke' if v == '{POKE}' else re.sub(r'\{[^}]*\}', '', v).strip()
    return out

def consts(path, prefix):
    out = {}
    for m in re.finditer(r'#define (' + prefix + r'\w+)\s+(0x[0-9A-Fa-f]+|\d+)', open(path).read()):
        out.setdefault(m.group(1), int(m.group(2), 0))
    return out

norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
TYPES = ['None', 'Normal', 'Fire', 'Water', 'Grass', 'Electric', 'Ice', 'Fighting', 'Poison', 'Ground', 'Flying',
         'Psychic', 'Bug', 'Rock', 'Ghost', 'Dragon', 'Dark', 'Steel']
tyname = lambda t: t.replace('TYPE_', '').capitalize()

# ---------------- type chart (Red: effectiveness combines through a table, not by multiplying)
src = open(D + '/src/dungeon_config.c').read()
chart_block = src[src.index('gTypeEffectivenessChart[NUM_TYPES][NUM_TYPES]'):]
chart_block = chart_block[:chart_block.index('};')]
eff_code = {'IMMUNE': 0, 'RESIST': 1, 'NEUTRAL': 2, 'SUPER': 3}
chart = {}
for m in re.finditer(r'\[TYPE_(\w+)\]\s*=\s*\{([^}]*)\}', chart_block):
    vals = [eff_code[v.strip()] for v in m.group(2).split(',') if v.strip()]
    chart[m.group(1).capitalize()] = dict(zip(TYPES, vals))
comb_block = src[src.index('gEffectivenessChart[NUM_EFFECTIVENESS]'):]
comb_block = comb_block[:comb_block.index('};\n')]
comb = [[0] * 4 for _ in range(4)]
for m in re.finditer(r'\[(IMMUNE|RESIST|NEUTRAL|SUPER)\]\s*=\s*\{([^}]*)\}', comb_block):
    for mm in re.finditer(r'\[(IMMUNE|RESIST|NEUTRAL|SUPER)\]\s*=\s*(IMMUNE|RESIST|NEUTRAL|SUPER)', m.group(2)):
        comb[eff_code[m.group(1)]][eff_code[mm.group(1)]] = eff_code[mm.group(2)]

# ---------------- moves
move_ids = consts(D + '/include/constants/move_id.h', 'MOVE_')
move_names = names_from_s(D + '/data/move/move_names.s', 'MoveName')
mdata = J(D + '/data/move/move_data.json')
RM = J(R + '/MOVES.json')
rm_by_norm = {norm(k): (k, v) for k, v in RM.items()}
RANGE = {'MOVE_RANGE_FRONT_FOE': 'front', 'MOVE_RANGE_USER': 'user', 'MOVE_RANGE_USER_2': 'user', 'MOVE_RANGE_USER_3': 'user',
         'MOVE_RANGE_CUTS_CORNERS_FOE': 'front_corners', 'MOVE_RANGE_CUTS_CORNERS': 'front_corners', 'MOVE_RANGE_STRAIGHT_LINE': 'line',
         'MOVE_RANGE_ROOM_FOES': 'room', 'MOVE_RANGE_ROOM': 'room_all', 'MOVE_RANGE_ROOM_EXCEPT_USER': 'room_all', 'MOVE_RANGE_ROOM_ONLY': 'room_all',
         'MOVE_RANGE_ONE_TILE_FOE': 'front', 'MOVE_RANGE_ONE_TILE': 'front', 'MOVE_RANGE_FRONT': 'front', 'MOVE_RANGE_TWO_TILES_FOE': 'two_tiles',
         'MOVE_RANGE_TWO_TILES': 'two_tiles', 'MOVE_RANGE_ROOM_ALLIES': 'team_room', 'MOVE_RANGE_FLOOR_MEMBERS': 'team_floor',
         'MOVE_RANGE_FLOOR_MEMBERS_2': 'team_floor', 'MOVE_RANGE_FLOOR_POKEMON': 'floor_all', 'MOVE_RANGE_FLOOR_FOES': 'floor_foes',
         'MOVE_RANGE_FLOOR': 'floor', 'MOVE_RANGE_FLOOR_2': 'floor', 'MOVE_RANGE_SIDE': 'adjacent', 'MOVE_RANGE_SIDE_FOE': 'adjacent',
         'MOVE_RANGE_THREE_TILES_DIAGONALLY': 'front_spread', 'MOVE_RANGE_SPECIAL': 'special', 'MOVE_RANGE_WALL': 'wall',
         'MOVE_RANGE_ITEMS': 'items', 'MOVE_RANGE_NONE': 'none'}
SPECIAL_TYPES = {'Fire', 'Water', 'Grass', 'Electric', 'Ice', 'Psychic', 'Dragon', 'Dark'}   # Gen 3 split, as in Red
moves, id2move = {}, {}
for cname, idx in move_ids.items():
    if idx >= len(mdata) or idx == 0: continue
    d = mdata[idx]
    nm = move_names.get(d['name'])
    if not nm and d['name'].startswith('MonsterCategory'):   # Red shares these strings with Pokemon categories
        nm = re.sub(r'(?<!^)(?=[A-Z])', ' ', d['name'][len('MonsterCategory'):])
    if not nm: continue
    t = tyname(d['type'])
    o = {'id': idx, 'name': nm, 't': t, 'p': d['basePower'], 'pp': d['basePP'], 'a1': d['accuracy1'], 'a2': d['accuracy2'],
         'crit': d.get('critChance', 0), 'hits': d.get('numberOfChainedHits', 1), 'ai': d.get('aiWeight', 0),
         'r': RANGE.get(d['rangeID'], 'front'), 'range_id': d['rangeID'].replace('MOVE_RANGE_', '').lower(),
         'c': 'X' if d['basePower'] == 0 else ('S' if t in SPECIAL_TYPES else 'P')}
    if d.get('cannotHitFrozen'): o['nofrozen'] = 1
    k = rm_by_norm.get(norm(nm))
    if k and k[1].get('c') == 'X':   # Red stores a small power on some status moves (Charm etc.); they still deal no damage
        o['c'] = 'X'
    if k:   # effect descriptors the old remake worked out for each Red move
        for key in ('eff', 'heal', 'drain', 'recoil', 'fixed', 'weather', 'ohko', 'selfko', 'cure', 'blow', 'warp', 'haze', 'metro', 'transform', 'sketch', 'hpcost'):
            if key in k[1]: o[key] = k[1][key]
    moves[nm] = o; id2move[cname] = nm
# moves that only exist after Red (for Pokemon past #386): keep the remake's version in Red's format
for k, v in RM.items():
    if k in moves or norm(k) in {norm(x) for x in moves}: continue
    o = {'id': -1, 'name': k, 't': v['t'], 'p': v.get('p', 0), 'pp': v['pp'], 'a1': v['a'], 'a2': v['a2'], 'crit': v.get('critP', 12),
         'hits': v.get('hits', 1) if isinstance(v.get('hits', 1), int) else 1, 'ai': 10, 'r': {'room': 'room', 'line': 'line', 'corner': 'front_corners'}.get(v.get('r', ''), 'front'),
         'c': v['c'], 'post_red': 1}
    for key in ('eff', 'heal', 'drain', 'recoil', 'fixed', 'weather', 'ohko', 'selfko', 'cure', 'blow', 'haze', 'hpcost'):
        if key in v: o[key] = v[key]
    moves[k] = o
moves['Regular Attack'] = {'id': 0, 'name': 'Attack', 't': 'None', 'p': 1, 'pp': 0, 'a1': 125, 'a2': 125, 'crit': 12, 'hits': 1, 'ai': 0, 'r': 'front', 'c': 'P'}
json.dump(moves, open(OUT + '/moves.json', 'w'), separators=(',', ':'))

# ---------------- species
mon_names = names_from_s(D + '/data/monster/monster_names.s', 'MonsterName')
mons = J(D + '/data/monster/monster_data.json')
learn = J(D + '/data/monster/learnset/learnset_data.json')
mon_ids = consts(D + '/include/constants/monster.h', 'MONSTER_')
abil_ids = consts(D + '/include/constants/ability.h', 'ABILITY_')
RS = J(R + '/SPECIES.json'); PMD = J(R + '/PMD.json'); MAN = J(R + '/MAN.json')
learn_by_name = {}
for i, e in enumerate(learn):
    learn_by_name.setdefault(norm(e['pokemon']), e)
def mv(cname):
    return id2move.get(cname)
species = {}
red_names = set()
for i, d in enumerate(mons):
    nm = mon_names.get(d['name'])
    if not nm or i == 0: continue
    key = None
    for k, v in RS.items():
        if norm(v['name']) == norm(nm) and not v.get('megaBase') and len(k) == 4:
            key = k; break
    if not key or key in species: continue
    red_names.add(key)
    L = learn_by_name.get(norm(nm))
    lv = [[x['level'], mv(x['move'])] for x in (L['levelUpMoves'] if L else []) if mv(x['move'])]
    tms = [mv(x) for x in (L['HMTMMoves'] if L else []) if mv(x)]
    s = {'name': nm, 'types': [tyname(t) for t in d['types'] if t != 'TYPE_NONE'], 'ab': [a.replace('ABILITY_', '').lower().replace('_', '-') for a in d['abilities'] if a != 'ABILITY_UNKNOWN'],
         'learn': lv, 'tm': tms, 'exp': d['expYield'], 'recruit': d['recruitRate'], 'size': d['bodySize'], 'shadow': d['shadowSize'],
         'regen': d['regenSpeed'], 'asleep': d['chanceAsleep'], 'speed': d['movementSpeed'], 'move': d['canMove'], 'red': 1,
         'friend': d['friendArea'].replace('FRIEND_AREA_', '').lower()}
    species[key] = s
for k, v in RS.items():
    if k in species: continue
    lv = [[l, n] for l, n in v['learn'] if n in moves]
    s = {'name': v['name'], 'types': v['types'], 'ab': v.get('ab', []), 'learn': lv, 'tm': [], 'exp': v.get('xp', 100) // 4,
         'recruit': 0 if v.get('lg') else 50, 'size': 1, 'shadow': 1, 'regen': 100, 'asleep': 8, 'speed': 1, 'move': True,
         'b': v['b'], 'red': 0}
    if v.get('megaBase'): s['megaBase'] = v['megaBase']; s['mul'] = v['mul']
    if v.get('lg'): s['legend'] = 1
    if v.get('pre'): s['pre'] = v['pre']
    species[k] = s
for k, v in RS.items():
    if k in species and v.get('pre'): species[k]['pre'] = v['pre']
json.dump(species, open(OUT + '/species.json', 'w'), separators=(',', ':'))
json.dump({'mon': PMD['mon'], 'curve': PMD['curve'], 'xp': PMD['xp']}, open(OUT + '/growth.json', 'w'), separators=(',', ':'))
json.dump(J(R + '/EVO.json'), open(OUT + '/evo.json', 'w'), separators=(',', ':'))

# ---------------- items: gameplay descriptors from the remake, Red's prices/names where they exist
RI = J(R + '/ITEMS.json')
item_names = names_from_s(D + '/data/item/item_names.s', 'ItemName')
idata = J(D + '/data/item/item_data.json')
red_items = {}
for d in idata:
    nm = item_names.get(d['name'])
    if nm: red_items[norm(nm)] = d
desc_s = open(D + '/data/item/item_descriptions.s', encoding='utf8', errors='replace').read()
descs = {m.group(1): re.sub(r'\{NEW_LINE\}', ' ', m.group(2)).replace('\\n', ' ').replace('\\0', '').strip()
         for m in re.finditer(r'\n(ItemDescription\w+):\s*\n\.string "((?:[^"\\]|\\.)*)"', desc_s)}
CAT = {'CATEGORY_THROWN_LINE': 'Throw', 'CATEGORY_THROWN_ARC': 'Throw', 'CATEGORY_BERRIES_SEEDS_VITAMINS': 'Berry', 'CATEGORY_FOOD_GUMMIES': 'Food',
       'CATEGORY_HELD_ITEMS': 'Held', 'CATEGORY_TMS_HMS': 'TM', 'CATEGORY_POKE': 'Money', 'CATEGORY_ORBS': 'Orb', 'CATEGORY_LINK_BOX': 'Box',
       'CATEGORY_USED_TM': 'TM', 'CATEGORY_OTHER': 'Other'}
items = {}
rem_by_norm = {norm(v['name']): (k, v) for k, v in RI.items()}
for i, d in enumerate(idata):
    nm = item_names.get(d['name'])
    if not nm or i == 0: continue
    hit = rem_by_norm.get(norm(nm))
    k = hit[0] if hit else norm(nm)
    o = dict(hit[1]) if hit else {'id': k, 'name': nm, 'kind': 'red_' + d['actionType'].replace('ITEM_ACTION_TYPE_', '').lower(), 'v': 0,
                                  'stack': d['category'] in ('CATEGORY_THROWN_LINE', 'CATEGORY_THROWN_ARC'),
                                  'throwable': d['category'] in ('CATEGORY_THROWN_LINE', 'CATEGORY_THROWN_ARC')}
    o.update({'id': k, 'name': nm, 'red_id': i, 'price': d['buyPrice'], 'sell': d['sellPrice'], 'red': 1, 'cat': CAT.get(d['category'], o.get('cat', 'Other')),
              'red_cat': d['category'].replace('CATEGORY_', '').lower(), 'action': d['actionType'].replace('ITEM_ACTION_TYPE_', '').lower(),
              'desc': descs.get(d['description'], o.get('desc', '')), 'sprite': d.get('spriteID', 0), 'pal': d.get('paletteID', 0)})
    if d.get('spawnAmountRange') and d['spawnAmountRange'] != [0, 0]: o['amt'] = d['spawnAmountRange']
    if d['category'] == 'CATEGORY_POKE': k = 'poke'; o['id'] = 'poke'; o['kind'] = 'money'
    items[k] = o
for k, v in RI.items():   # items the remake added (Mega Stone, evolution items for later Pokemon...)
    if k not in items and norm(v['name']) not in {norm(x['name']) for x in items.values()}:
        o = dict(v); o['red'] = 0; items[k] = o
json.dump(items, open(OUT + '/items.json', 'w'), separators=(',', ':'))

# Fairy is added by the post-step in gen_types_fairy (Red has no Fairy)
json.dump({'chart': chart, 'combine': comb, 'types': TYPES}, open(OUT + '/types.json', 'w'), separators=(',', ':'))
print('moves', len(moves), 'red', sum(1 for m in moves.values() if m['id'] > 0), '| species', len(species), 'red', len(red_names), '| items', len(items), 'red', sum(1 for i in items.values() if i.get('red')))
print('chart Fire->Grass', chart['Fire']['Grass'], 'combine', comb)
print(species['0016']); print(moves['Tackle'], moves['Ember'], moves['Razor Leaf'])
