#!/usr/bin/env python3
"""Add Explorers of Sky (PMD: Explorers Remixed 2.3) items to game/data/items.json.

Source: the user's patched Remixed ROM (BALANCE/item_p.bin + MESSAGE/text_e.str), extracted to
/tmp/claude-0/eos_remix/items_all.json. Items that already exist (same name as a Red / other item) are
kept as they are; everything else is added with an "eos" block describing its effect, parsed from the
in-game description. Exclusive items (category 15) get "excl": {for: [species keys] | types: [..], eff: [...]}.
Run again safely: it removes the items it added before (eos: 1) first.
"""
import json, re

G = '/tmp/claude-0/pmd1/game/data'
E = json.load(open('/tmp/claude-0/eos_remix/items_all.json'))
items = json.load(open(f'{G}/items.json'))
species = json.load(open(f'{G}/species.json'))
moves = json.load(open(f'{G}/moves.json'))

items = {k: v for k, v in items.items() if not v.get('eos_added')}
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
by_name = {}
for k, v in items.items():
    by_name.setdefault(norm(v['name']), k)
for k, v in list(items.items()):
    if v.get('red_cat') == 'tms_hms':
        by_name.setdefault(norm('TM ' + v['name']), k)

CAT = {0: 'thrown_line', 1: 'thrown_arc', 2: 'berries_seeds_vitamins', 3: 'food_gummies', 4: 'held_items',
       5: 'tms_hms', 6: 'poke', 8: 'other', 9: 'orbs', 10: 'link_box', 11: 'used_tm', 12: 'other', 13: 'other',
       14: 'other', 15: 'exclusive'}
SHOWCAT = {0: 'Throw', 1: 'Throw', 2: 'Seed', 3: 'Food', 4: 'Held', 5: 'TM', 8: 'Special', 9: 'Orb', 15: 'Exclusive', 12: 'Box', 13: 'Box', 14: 'Box'}
JUNK = re.compile(r'^(\$\$\$|Unused|Nothing$|Gravelyrock|Oren Berry|No-Slip Cap|Y-Ray Specs|Gaggle Specs|Gone Pebble|Dummy)')
TYPES = ['Normal', 'Fire', 'Water', 'Grass', 'Electric', 'Ice', 'Fighting', 'Poison', 'Ground', 'Flying', 'Psychic',
         'Bug', 'Rock', 'Ghost', 'Dragon', 'Dark', 'Steel', 'Fairy']
STAT = {'attack speed': None, 'special attack': 'spa', 'special defense': 'spd', 'attack': 'atk', 'defense': 'def', 'special': 'spa'}
STATUS = {'cringe': 'cringe', 'confused': 'confused', 'paralysis': 'para', 'burn': 'burn', 'frozen': 'frozen', 'sleep': 'sleep',
          'shadow hold': 'shadow_hold', 'blinker': 'blinker', 'infatuated': 'infatuated', 'perish song': 'perish',
          'constriction': 'constriction', 'nightmare': 'nightmare', 'poisoned': 'poison'}
WEATHER = {'clear': 'clear', 'rain': 'rain', 'sunny': 'sunny', 'cloudy': 'cloudy', 'hail': 'hail', 'fog': 'fog', 'sandstorm': 'sandstorm', 'snow': 'snow'}

def stats_in(t):
    out = {}
    t = t.replace('Special. Attack', 'Special Attack')
    for part in re.split(r',| and ', t):
        p = part.strip().lower().rstrip('.')
        for nm, key in sorted(STAT.items(), key=lambda x: -len(x[0])):
            if p.endswith(nm) and key:
                out[key] = out.get(key, 0) + 1
                break
    return out

def parse_effects(d):
    """Effect list from an EoS/Remixed item description."""
    t = d.replace('Pokemon', 'Pokémon')
    effs = []
    m = re.search(r'[Ss]lightly (?:boosts|raises) (?:the )?((?:Attack|Defense|Special Attack|Special Defense|Special\. Attack|Special)(?:(?:,| and|, and) (?:Attack|Defense|Special Attack|Special Defense|Special\. Attack|Special))*)', t)
    if m:
        effs.append({'stat': stats_in(m.group(1))})
    if re.search(r'[Bb]oosts (?:the )?(?:Pokémon\'s )?maximum HP', t):
        effs.append({'maxhp': 5})
    if re.search(r'[Bb]oosts (?:the )?maximum PP', t):
        effs.append({'maxpp': 1})
    m = re.search(r'Absorbs damage from (\w+)-type moves', t)
    if m: effs.append({'absorb': m.group(1)})
    m = re.search(r'Prevents (\w+)-type moves from damaging', t)
    if m: effs.append({'immune': m.group(1)})
    m = re.search(r'May afflict (?:attacking enemies|an attacking enemy)(?: of the opposite gender)? with (?:a |an |the )?(.+?) status', t)
    if m:
        s = m.group(1).lower()
        lst = [STATUS[k] for k in STATUS if k in s]
        if lst: effs.append({'on_hit': lst, 'ch': 12})
    m = re.search(r'Protects the Pokémon from (?:a |an )?(.+?) status', t)
    if m:
        s = m.group(1).lower()
        effs.append({'protect': [STATUS[k] for k in STATUS if k in s] or ['all']})
    if re.search(r'from all status problems|prevents all status problems', t, re.I):
        w = re.search(r'During a (\w+) condition', t)
        effs.append({'protect': ['all'], 'weather': WEATHER.get(w.group(1).lower()) if w else None})
    m = re.search(r'During a (\w+) condition, (?:boosts|protects)[^.]*?(Movement Speed|evasiveness|status problems)', t)
    if m:
        w = WEATHER.get(m.group(1).lower(), m.group(1).lower())
        k = {'Movement Speed': 'weather_speed', 'evasiveness': 'weather_eva', 'status problems': 'weather_protect'}[m.group(2)]
        if not any('protect' in e for e in effs) or k != 'weather_protect':
            effs.append({k: w})
    m = re.search(r'Attack Speed by 1 level during a (\w+) condition|During a (\w+) condition, boosts Attack Speed', t)
    if m:
        effs.append({'weather_speed': WEATHER.get((m.group(1) or m.group(2)).lower())})
    if re.search(r'taking critical hits', t): effs.append({'no_crit': 1})
    if re.search(r'ignore (?:the effects of an enemy\'s )?Reflect and Light Screen', t): effs.append({'ignore_screens': 1})
    if re.search(r'Speeds up the Pokémon\'s natural HP healing', t): effs.append({'regen': 1})
    if re.search(r'restore the PP of one of the Pokémon\'s moves upon taking damage', t): effs.append({'pp_on_hit': 1})
    if re.search(r'Halves Selfdestruct and explosion damage', t): effs.append({'explosion': 0.5})
    if re.search(r'Nearly eliminates all damage taken from any explosion', t): effs.append({'explosion': 0.1})
    if re.search(r'bonus Exp|extra Experience Points|bonus Experience', t): effs.append({'exp_bonus': 1})
    if re.search(r'Exp\. Points every time (?:the Pokémon|it) takes damage|Exp\. Points every time it takes damage', t): effs.append({'exp_on_hit': 1})
    if re.search(r'Any Berry or Apple eaten will recover HP', t): effs.append({'berry_heal': 1})
    if re.search(r'Protects against weather damage|shields the Pokémon from weather', t): effs.append({'weather_proof': 1})
    if re.search(r'counterstrike against Physical Attacks', t): effs.append({'counter': 1.0})
    if re.search(r'Returns 1/4 damage from Physical Attacks', t): effs.append({'counter': 0.25})
    if re.search(r'seal one of an enemy\'s known moves', t): effs.append({'seal_on_hit': 1})
    if re.search(r'move with no PP consumption', t): effs.append({'free_pp': 1})
    if re.search(r'Absorb and other HP-draining moves restore', t): effs.append({'drain_boost': 1})
    if re.search(r'from being hit by thrown items', t): effs.append({'dodge_throw': 1})
    if re.search(r'thrown or hurled items? bounce|bounce a thrown or hurled item', t): effs.append({'bounce_throw': 1})
    if re.search(r'instead leaving it with 1 HP', t): effs.append({'endure': 1})
    if re.search(r'Halves damage Physical Attacks do', t): effs.append({'half_physical': 1})
    if re.search(r'Halves damage (?:received from Special Attacks|Special Attack moves do)', t): effs.append({'half_special': 1})
    if re.search(r'warp the Pokémon away if it is attacked while its HP is low', t): effs.append({'warp_low': 1})
    if re.search(r'Long Toss status', t): effs.append({'long_toss': 1})
    if re.search(r'Ghost-type enemies (?:with|using) Normal- and Fighting-type moves', t): effs.append({'ghost_hit': 1})
    if re.search(r'Dark-type enemies using Psychic-type moves', t): effs.append({'dark_hit': 1})
    if re.search(r'HP fully when it reaches a new floor', t): effs.append({'floor_heal': 1})
    if re.search(r'1 PP to all of the Pokémon\'s moves when it reaches a new floor', t): effs.append({'floor_pp': 1})
    if re.search(r'having its moves disabled', t): effs.append({'no_disable': 1})
    if re.search(r'Pressure ability', t): effs.append({'pressure_boost': 1})
    if re.search(r'status of Invisible when it is attacked', t): effs.append({'invis_on_hit': 1})
    if re.search(r'Movement Speed by 1 level when it is attacked', t): effs.append({'speed_on_hit': 1})
    if re.search(r'damage the Pokémon inflicts by 1\.5 times', t): effs.append({'dmg_mult': 1.5})
    if re.search(r'Halves the damage the Pokémon takes', t): effs.append({'dmg_taken': 0.5})
    if re.search(r'phase through walls', t): effs.append({'mobile': 1})
    if re.search(r'defeated foes to drop some|chance of finding money after defeating', t): effs.append({'money': 1})
    if re.search(r'bounce (?:received )?moves (?:that cause status problems )?back', t): effs.append({'bounce_status': 1})
    if re.search(r'reduce the Movement Speed of attacking enemies', t): effs.append({'on_hit': ['slow'], 'ch': 12})
    if re.search(r'boosts the power of the Pokémon\'s moves', t): effs.append({'dmg_mult': 1.2})
    m = re.search(r'boosts the Pokémon\'s (Attack|Defense|Special Attack|Special Defense)(?:, (Attack|Defense|Special Attack|Special Defense))*', t)
    if m and not any('stat' in e for e in effs):
        effs.append({'stat': stats_in(m.group(0).split("Pokémon's ")[1])})
    if re.search(r'inflicts Burn on the holder', t): effs.append({'holder_status': 'burn'})
    if re.search(r'inflicts Badly Poisoned on the holder', t): effs.append({'holder_status': 'badpoison'})
    return effs

def species_for(d):
    m = re.search(r'(?:team members|Works for):? (.+?)\.(?: |$)', d) or re.search(r"to the team's (.+?)\.(?: |$)", d)
    if not m:
        m2 = re.search(r'Item for: (.+?) [A-Z][a-z]', d)
        k = SP_BY_NAME.get(norm(m2.group(1))) if m2 else None
        return [k] if k else []
    names = re.split(r',\s*|\s+and\s+|,\s+and\s+', m.group(1))
    out = []
    for n in names:
        n = n.strip().replace('and ', '')
        k = SP_BY_NAME.get(norm(n))
        if k:
            out.append(k)
    return out

SP_BY_NAME = {}
for k, v in species.items():
    if len(k) == 4:
        SP_BY_NAME.setdefault(norm(v.get('name', '')), k)
for pre, rep in [('h', 'hisuian'), ('a', 'alolan'), ('g', 'galarian'), ('p', 'paldean')]:
    for k, v in list(species.items()):
        if len(k) == 4:
            SP_BY_NAME.setdefault(pre + norm(v.get('name', '')), k)

# EoS item sprite -> the Red item sprite / palette of the same item (for the icon atlas)
import collections
SPR = collections.defaultdict(collections.Counter)
for e in E:
    k = by_name.get(norm(e['name']))
    if k and items[k].get('red') and 'sprite' in items[k]:
        SPR[e['sprite']][(items[k]['sprite'], items[k].get('pal', 0))] += 1
FALLBACK = {0: 'ironthorn', 1: 'gravelerock', 2: 'plainseed', 3: 'apple', 4: 'defscarf', 5: 'icebeam', 8: 'wishstone',
            9: 'escapeorb', 10: 'linkbox', 12: 'wishstone', 13: 'wishstone', 14: 'wishstone', 15: 'defscarf'}
def icon_of(e):
    c = SPR.get(e['sprite'])
    if c:
        return c.most_common(1)[0][0]
    f = items.get(FALLBACK.get(e['cat'], 'wishstone'), {})
    return (f.get('sprite', 0), f.get('pal', 0))

added = 0
excl = 0
seen_names = set()
for e in E:
    nm = e['name'].strip()
    if not nm or JUNK.match(nm) or e['cat'] in (6, 7, 11):
        continue
    key0 = norm(nm)
    if e['cat'] == 5:
        if moves.get(nm) is None and moves.get(nm.replace('-', ' ')) is None:
            continue                                     # a TM for a move the game doesn't have
        if key0 in by_name or norm('TM ' + nm) in by_name:
            continue
    elif key0 in by_name:
        continue
    if (key0, e['cat']) in seen_names:
        continue
    seen_names.add((key0, e['cat']))
    key = key0 if key0 not in items else 'eos' + key0
    if e['cat'] in (12, 13, 14):
        key = key0 + ('', 'b', 'c')[e['cat'] - 12]
        if key in items:
            continue
    it = {'id': key, 'name': nm, 'desc': e['desc'].replace(' Select detail: or /View detail:', ''), 'cat': SHOWCAT.get(e['cat'], 'Special'),
          'price': e['buy'], 'sell': e['sell'], 'red_cat': CAT.get(e['cat'], 'other'), 'eos_added': 1, 'eos_id': e['id'],
          'eos_sprite': e['sprite'], 'eos_pal': e['pal'], 'stack': e['cat'] in (0, 1), 'throwable': e['cat'] in (0, 1),
          'amt': [e['rmin'], e['rmax']] if e['cat'] in (0, 1) else None}
    it['sprite'], it['pal'] = icon_of(e)
    if e['cat'] in (0, 1):
        it['kind'] = 'line' if e['cat'] == 0 else 'arc'
        it['action'] = 'throwable' if e['cat'] == 0 else 'rocks'
    elif e['cat'] == 5:
        it['kind'] = 'red_tm'
        it['action'] = 'tm'
        it['v'] = nm
    elif e['cat'] == 9:
        it['kind'] = 'eos_orb'
        it['action'] = 'orbs'
    elif e['cat'] == 2:
        it['action'] = 'food'
        it['kind'] = {'X-Eye Seed': 'confuse_x', 'Gabite Scale': 'cure', 'Golden Seed': 'golden', 'Vile Seed': 'vile',
                      'Vanish Seed': 'vanish', 'Nectar': 'nectar', 'Dropeye Seed': 'dropeye', 'Reviser Seed': 'plain',
                      'Slip Seed': 'slip', 'Via Seed': 'warp', 'Mix Elixir': 'mixelixir', 'Dough Seed': 'plain'}.get(nm, 'plain')
    elif e['cat'] == 3:
        it['action'] = 'food'
        it['kind'] = 'iqgummi' if 'Gummi' in nm else 'golden_apple' if nm == 'Golden Apple' else 'food'
        if it['kind'] == 'iqgummi':
            it['v'] = 'Fairy'
    elif e['cat'] == 4:
        it['action'] = 'scarfs'
        it['kind'] = 'held'
        it['eos'] = parse_effects(e['desc'])
    elif e['cat'] == 15:
        it['action'] = 'exclusive'
        it['kind'] = 'exclusive'
        effs = parse_effects(e['desc'])
        tm = re.search(r'Item for: (\w+)-type Pok', e['desc'])
        it['excl'] = {'for': species_for(e['desc']), 'types': [tm.group(1)] if tm else [], 'eff': effs}
        excl += 1
    else:
        it['action'] = 'misc'
        it['kind'] = 'eos_misc'
    if it.get('amt') is None:
        it.pop('amt')
    items[key] = it
    by_name[key0] = key
    added += 1

json.dump(items, open(f'{G}/items.json', 'w'), ensure_ascii=False, indent=None, separators=(',', ':'))
ex = [v for v in items.values() if v.get('kind') == 'exclusive']
no_eff = [v['name'] for v in ex if not v['excl']['eff']]
no_for = [v['name'] for v in ex if not v['excl']['for'] and not v['excl']['types']]
print('added', added, 'exclusive', excl, 'without parsed effect', len(no_eff), 'without species', len(no_for))
print('no effect:', no_eff[:40])
print('no species:', no_for[:20])
held = [v for v in items.values() if v.get('eos_added') and v.get('kind') == 'held']
print('held', len(held), [(v['name'], v.get('eos')) for v in held][:30])
