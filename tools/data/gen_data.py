#!/usr/bin/env python3
"""Build game/data/{moves,species,growth,evo,items,types}.json (stage 1).
Red Rescue Team tables (pmd-red decomp) are the source of truth for every Pokemon, move and item that exists in Red.
Pokemon/moves/items after Red come from the old prototype's tables, rebuilt from PokeAPI + Red's numbers by proto.py.
Stage 2 (tools/data/convert_remix.py, gen_eos_items.py, gen_megas_dx.py, tools/fx/build_moves.py ...) adds Explorers
of Sky / Remixed content on top of these files."""
import json
import os
import re
import sys

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
import proto  # noqa: E402
import redsrc  # noqa: E402
from redsrc import consts, names_from_s  # noqa: E402

norm = redsrc.norm
TYPES = ['None', 'Normal', 'Fire', 'Water', 'Grass', 'Electric', 'Ice', 'Fighting', 'Poison', 'Ground', 'Flying',
         'Psychic', 'Bug', 'Rock', 'Ghost', 'Dragon', 'Dark', 'Steel']
tyname = lambda t: t.replace('TYPE_', '').capitalize()
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
EFFECT_KEYS_RED = ('eff', 'heal', 'drain', 'recoil', 'fixed', 'weather', 'ohko', 'selfko', 'cure', 'blow', 'warp', 'haze', 'metro',
                   'transform', 'sketch', 'hpcost')
EFFECT_KEYS_NEW = ('eff', 'heal', 'drain', 'recoil', 'fixed', 'weather', 'ohko', 'selfko', 'cure', 'blow', 'haze', 'hpcost')
CAT = {'CATEGORY_THROWN_LINE': 'Throw', 'CATEGORY_THROWN_ARC': 'Throw', 'CATEGORY_BERRIES_SEEDS_VITAMINS': 'Berry', 'CATEGORY_FOOD_GUMMIES': 'Food',
       'CATEGORY_HELD_ITEMS': 'Held', 'CATEGORY_TMS_HMS': 'TM', 'CATEGORY_POKE': 'Money', 'CATEGORY_ORBS': 'Orb', 'CATEGORY_LINK_BOX': 'Box',
       'CATEGORY_USED_TM': 'TM', 'CATEGORY_OTHER': 'Other'}
# Fairy (not in Red): main-series matchups on Red's scale (0 immune, 1 resisted, 2 neutral, 3 super effective)
FAIRY_ATTACK = {'Fire': 1, 'Fighting': 3, 'Poison': 1, 'Dragon': 3, 'Dark': 3, 'Steel': 1}
FAIRY_DEFEND = {'Fighting': 1, 'Poison': 3, 'Bug': 1, 'Dragon': 0, 'Dark': 1, 'Steel': 3}


def save(name, obj):
    """Compact JSON, non-ASCII as \\u escapes (the format the game's data files have always had)."""
    with open(common.p(common.DATA, name), 'w', encoding='utf-8') as f:
        json.dump(obj, f, separators=(',', ':'))


def type_chart():
    src = redsrc.read('src/dungeon_config.c')
    block = src[src.index('gTypeEffectivenessChart[NUM_TYPES][NUM_TYPES]'):]
    block = block[:block.index('};')]
    code = {'IMMUNE': 0, 'RESIST': 1, 'NEUTRAL': 2, 'SUPER': 3}
    chart = {}
    for m in re.finditer(r'\[TYPE_(\w+)\]\s*=\s*\{([^}]*)\}', block):
        vals = [code[v.strip()] for v in m.group(2).split(',') if v.strip()]
        chart[m.group(1).capitalize()] = dict(zip(TYPES, vals))
    cb = src[src.index('gEffectivenessChart[NUM_EFFECTIVENESS]'):]
    cb = cb[:cb.index('};\n')]
    comb = [[0] * 4 for _ in range(4)]
    for m in re.finditer(r'\[(IMMUNE|RESIST|NEUTRAL|SUPER)\]\s*=\s*\{([^}]*)\}', cb):
        for mm in re.finditer(r'\[(IMMUNE|RESIST|NEUTRAL|SUPER)\]\s*=\s*(IMMUNE|RESIST|NEUTRAL|SUPER)', m.group(2)):
            comb[code[m.group(1)]][code[mm.group(1)]] = code[mm.group(2)]
    for t in TYPES:
        chart[t]['Fairy'] = FAIRY_DEFEND.get(t, 2)
    chart['Fairy'] = {t: FAIRY_ATTACK.get(t, 2) for t in TYPES + ['Fairy']}
    return {'chart': chart, 'combine': comb, 'types': TYPES + ['Fairy']}


MOVES_DATA = os.path.join(common.TMP, 'eos', 'moveanim', 'moves_data.json')   # tools/fx/build_data.py (Remixed waza_p.bin)
RX_RANGE = {'front': 'front', 'front_cuts_corners': 'front_corners', 'two_tiles_away (cuts corners)': 'two_tiles',
            'straight_line': 'line', 'room': 'room', 'around (8 tiles)': 'adjacent',
            'front_and_sides (3 tiles, like Wide Slash)': 'front_spread', 'two_tiles_cuts_corners': 'front'}


def remixed_numbers(moves):
    """Moves after Red that Explorers of Sky / Remixed has: take its numbers (type, power, PP, accuracy, crit, hits,
    category, range) instead of the prototype's estimates; marked src = 'remixed'."""
    md = {}
    for k, v in common.load_json(common.need(MOVES_DATA, 'moves_data.json (run tools/eos/extract.py, tools/fx/build_data.py)')).items():
        md.setdefault(norm(k.split(' #')[0]), v)
    for k, o in moves.items():
        m = md.get(norm(k))
        if o['id'] != -1 or not m:
            continue
        o['t'] = m['type']
        if m['power'] > 1:
            o['p'] = m['power']
        o['pp'] = m['pp']
        o['a1'], o['a2'] = m['accuracy2'], m['accuracy1']    # build_data.py's labels are swapped (byte 10 is accuracy 1)
        o['crit'] = m['crit']
        o['hits'] = m['hits']
        o['c'] = {'physical': 'P', 'special': 'S', 'status': 'X'}[m['category']]
        rg, tg = m['range']['range'], m['range']['target']
        if tg == 'enemies' and rg in RX_RANGE:
            o['r'] = RX_RANGE[rg]
        elif tg == 'user' and rg == 'user':
            o['r'] = 'user'
        elif tg == 'allies' and rg == 'room':
            o['r'] = 'team_room'
        o['src'] = 'remixed'


def main():
    P = proto.build_all()
    RM, RS, RI, PMD = P['MOVES'], P['SPECIES'], P['ITEMS'], P['PMD']

    # ---------------- moves
    move_ids = consts('include/constants/move_id.h', 'MOVE_')
    move_names = names_from_s('data/move/move_names.s', 'MoveName')
    mdata = redsrc.load('data/move/move_data.json')
    rm_by_norm = {norm(k): (k, v) for k, v in RM.items()}
    moves, id2move = {}, {}
    for cname, idx in move_ids.items():
        if idx >= len(mdata) or idx == 0:
            continue
        d = mdata[idx]
        nm = move_names.get(d['name'])
        if not nm and d['name'].startswith('MonsterCategory'):   # Red shares these strings with Pokemon categories
            nm = re.sub(r'(?<!^)(?=[A-Z])', ' ', d['name'][len('MonsterCategory'):])
        if not nm:
            continue
        t = tyname(d['type'])
        o = {'id': idx, 'name': nm, 't': t, 'p': d['basePower'], 'pp': d['basePP'], 'a1': d['accuracy1'], 'a2': d['accuracy2'],
             'crit': d.get('critChance', 0), 'hits': d.get('numberOfChainedHits', 1), 'ai': d.get('aiWeight', 0),
             'r': RANGE.get(d['rangeID'], 'front'), 'range_id': d['rangeID'].replace('MOVE_RANGE_', '').lower(),
             'c': 'X' if d['basePower'] == 0 else ('S' if t in SPECIAL_TYPES else 'P')}
        if d.get('cannotHitFrozen'):
            o['nofrozen'] = 1
        k = rm_by_norm.get(norm(nm))
        if k and k[1].get('c') == 'X':   # Red stores a small power on some status moves (Charm etc.); they still deal no damage
            o['c'] = 'X'
        if k:   # effect descriptors of the prototype for each Red move
            for key in EFFECT_KEYS_RED:
                if key in k[1]:
                    o[key] = k[1][key]
        moves[nm] = o
        id2move[cname] = nm
    red_norms = {norm(x) for x in moves}
    for k, v in RM.items():   # moves after Red (for Pokemon past #386): the prototype's version in Red's format
        if k in moves or norm(k) in red_norms:
            continue
        o = {'id': -1, 'name': k, 't': v['t'], 'p': v.get('p', 0), 'pp': v['pp'], 'a1': v['a'], 'a2': v['a2'], 'crit': v.get('critP', 12),
             'hits': v.get('hits', 1) if isinstance(v.get('hits', 1), int) else 1, 'ai': 10,
             'r': {'room': 'room', 'line': 'line', 'corner': 'front_corners'}.get(v.get('r', ''), 'front'), 'c': v['c'], 'post_red': 1}
        for key in EFFECT_KEYS_NEW:
            if key in v:
                o[key] = v[key]
        moves[k] = o
    remixed_numbers(moves)
    moves['Regular Attack'] = {'id': 0, 'name': 'Attack', 't': 'None', 'p': 1, 'pp': 0, 'a1': 125, 'a2': 125, 'crit': 12, 'hits': 1, 'ai': 0,
                               'r': 'front', 'c': 'P'}
    save('moves.json', moves)

    # ---------------- species
    mon_names = names_from_s('data/monster/monster_names.s', 'MonsterName')
    mons = redsrc.load('data/monster/monster_data.json')
    learn = redsrc.load('data/monster/learnset/learnset_data.json')
    learn_by_name = {}
    for e in learn:
        learn_by_name.setdefault(norm(e['pokemon']), e)
    species = {}
    red_key = {}                       # Red monster index -> species key (first form of each Pokemon)
    for i, d in enumerate(mons):
        nm = mon_names.get(d['name'])
        if not nm or i == 0:
            continue
        key = None
        for k, v in RS.items():
            if norm(v['name']) == norm(nm) and not v.get('megaBase') and len(k) == 4:
                key = k
                break
        if not key or key in species:
            continue
        red_key[i] = key
        L = learn_by_name.get(norm(nm))
        lv = [[x['level'], id2move.get(x['move'])] for x in (L['levelUpMoves'] if L else []) if id2move.get(x['move'])]
        tms = [id2move.get(x) for x in (L['HMTMMoves'] if L else []) if id2move.get(x)]
        species[key] = {'name': nm, 'types': [tyname(t) for t in d['types'] if t != 'TYPE_NONE'],
                        'ab': [a.replace('ABILITY_', '').lower().replace('_', '-') for a in d['abilities'] if a != 'ABILITY_UNKNOWN'],
                        'learn': lv, 'tm': tms, 'exp': d['expYield'], 'recruit': d['recruitRate'], 'size': d['bodySize'],
                        'shadow': d['shadowSize'], 'regen': d['regenSpeed'], 'asleep': d['chanceAsleep'], 'speed': d['movementSpeed'],
                        'move': d['canMove'], 'red': 1, 'friend': d['friendArea'].replace('FRIEND_AREA_', '').lower()}
    for k, v in RS.items():
        if k in species:
            continue
        s = {'name': v['name'], 'types': v['types'], 'ab': v.get('ab', []), 'learn': [[lv, n] for lv, n in v['learn'] if n in moves],
             'tm': [], 'exp': v.get('xp', 100) // 4, 'recruit': 0 if v.get('lg') else 50, 'size': 1, 'shadow': 1, 'regen': 100,
             'asleep': 8, 'speed': 1, 'move': True, 'b': v['b'], 'red': 0}
        if v.get('megaBase'):
            s['megaBase'] = v['megaBase']
            s['mul'] = v['mul']
        if v.get('lg'):
            s['legend'] = 1
        if v.get('pre'):
            s['pre'] = v['pre']
        species[k] = s
    for k, v in RS.items():
        if k in species and v.get('pre'):
            species[k]['pre'] = v['pre']
    # Red's own body size value (monster_data "size", used by weight-based moves), by name (a Pokemon's first entry);
    # none where two different Red names normalise alike (Nidoran F / Nidoran M)
    sizes, raw = {}, {}
    for i, d in enumerate(mons):
        nm = mon_names.get(d['name'])
        if nm and i:
            sizes.setdefault(norm(nm), d['size'])
            raw.setdefault(norm(nm), set()).add(nm)
    for k, s in species.items():
        n = norm(s['name'])
        if n in sizes and len(raw[n]) == 1:
            s['rsize'] = sizes[n]
    save('species.json', species)
    save('growth.json', {'mon': PMD['mon'], 'curve': PMD['curve'], 'xp': PMD['xp']})
    save('evo.json', P['EVO'])

    # ---------------- items: gameplay descriptors of the prototype, Red's prices/names/descriptions where they exist
    item_names = names_from_s('data/item/item_names.s', 'ItemName')
    idata = redsrc.load('data/item/item_data.json')
    desc_s = redsrc.read('data/item/item_descriptions.s')
    descs = {m.group(1): re.sub(r'\{NEW_LINE\}', ' ', m.group(2)).replace('\\n', ' ').replace('\\0', '').strip()
             for m in re.finditer(r'\n(ItemDescription\w+):\s*\n\.string "((?:[^"\\]|\\.)*)"', desc_s)}
    items = {}
    rem_by_norm = {norm(v['name']): (k, v) for k, v in RI.items()}
    for i, d in enumerate(idata):
        nm = item_names.get(d['name'])
        if not nm or i == 0:
            continue
        hit = rem_by_norm.get(norm(nm))
        k = hit[0] if hit else norm(nm)
        o = dict(hit[1]) if hit else {'id': k, 'name': nm, 'kind': 'red_' + d['actionType'].replace('ITEM_ACTION_TYPE_', '').lower(), 'v': 0,
                                      'stack': d['category'] in ('CATEGORY_THROWN_LINE', 'CATEGORY_THROWN_ARC'),
                                      'throwable': d['category'] in ('CATEGORY_THROWN_LINE', 'CATEGORY_THROWN_ARC')}
        o.update({'id': k, 'name': nm, 'red_id': i, 'price': d['buyPrice'], 'sell': d['sellPrice'], 'red': 1,
                  'cat': CAT.get(d['category'], o.get('cat') or 'Other'), 'red_cat': d['category'].replace('CATEGORY_', '').lower(),
                  'action': d['actionType'].replace('ITEM_ACTION_TYPE_', '').lower(),
                  'desc': descs.get(d['description'], o.get('desc') or ''), 'sprite': d.get('spriteID', 0), 'pal': d.get('paletteID', 0)})
        if d.get('spawnAmountRange') and d['spawnAmountRange'] != [0, 0]:
            o['amt'] = d['spawnAmountRange']
        if d['category'] == 'CATEGORY_POKE':
            k = 'poke'
            o['id'] = 'poke'
            o['kind'] = 'money'
        items[k] = o
    have = {norm(x['name']) for x in items.values()}
    for k, v in RI.items():   # items the prototype added (Mega Stone, evolution items for later Pokemon...)
        if k not in items and norm(v['name']) not in have:
            o = dict(v)
            o['red'] = 0
            items[k] = o
    save('items.json', items)
    save('types.json', type_chart())
    print('moves', len(moves), 'red', sum(1 for m in moves.values() if m['id'] > 0), '| species', len(species), 'red', len(red_key),
          '| items', len(items), 'red', sum(1 for i in items.values() if i.get('red')))


if __name__ == '__main__':
    main()
