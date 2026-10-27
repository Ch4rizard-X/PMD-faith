#!/usr/bin/env python3
"""Rescue Team DX's Mega Evolutions (Empowerment Seed / Awakened): the species data (stage 2).
- adds the DX Megas the game was missing (stats, types, ability from PokeAPI; PMD stats = base form x Mega ratios)
- fixes every Mega's ability and types to its real Mega ability / types (PokeAPI)
Writes data/species.json only. The Mega sprite sheets / portraits (data/sprites.json, assets/sp/) are made by
gen_megas_sprites.py, which belongs to the sprites step.
"""
import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

def save_ascii(path, obj):
    """Compact JSON with non-ASCII escaped (the format the game's species/dungeons files have always had)."""
    with open(common.p(path), 'w', encoding='utf-8') as f:
        json.dump(obj, f, separators=(',', ':'))


PA = common.POKEAPI_CSV + os.sep
_csv = lambda n: csv.DictReader(open(PA + n, encoding='utf-8'))

pid_of = {r['identifier']: r['id'] for r in _csv('pokemon.csv')}
stats = {}
for r in _csv('pokemon_stats.csv'):
    stats.setdefault(r['pokemon_id'], {})[r['stat_id']] = int(r['base_stat'])
tname = {r['id']: r['identifier'].capitalize() for r in _csv('types.csv')}
types = {}
for r in _csv('pokemon_types.csv'):
    types.setdefault(r['pokemon_id'], []).append((int(r['slot']), tname[r['type_id']]))
abil = {r['id']: r['identifier'] for r in _csv('abilities.csv')}
pab = {}
for r in _csv('pokemon_abilities.csv'):
    pab.setdefault(r['pokemon_id'], []).append((int(r['slot']), abil[r['ability_id']]))
dex_name = {r['id']: r['identifier'] for r in _csv('pokemon_species.csv')}

st = lambda pid: [stats[pid][s] for s in ('1', '2', '3', '4', '5', '6')]   # hp atk def spa spd spe

NEW = {'0003M': ('venusaur-mega', '0001', 'Mega Venusaur'), '0006MY': ('charizard-mega-y', '0002', 'Mega Charizard Y'),
       '0009M': ('blastoise-mega', '0001', 'Mega Blastoise'), '0015M': ('beedrill-mega', '0001', 'Mega Beedrill'),
       '0018M': ('pidgeot-mega', '0001', 'Mega Pidgeot'), '0080M': ('slowbro-mega', '0002', 'Mega Slowbro'),
       '0127M': ('pinsir-mega', '0001', 'Mega Pinsir'), '0130M': ('gyarados-mega', '0001', 'Mega Gyarados'),
       '0150MX': ('mewtwo-mega-x', '0001', 'Mega Mewtwo X'), '0181M': ('ampharos-mega', '0001', 'Mega Ampharos'),
       '0212M': ('scizor-mega', '0001', 'Mega Scizor'), '0214M': ('heracross-mega', '0001', 'Mega Heracross'),
       '0254M': ('sceptile-mega', '0001', 'Mega Sceptile'), '0257M': ('blaziken-mega', '0001', 'Mega Blaziken'),
       '0260M': ('swampert-mega', '0001', 'Mega Swampert'), '0306M': ('aggron-mega', '0001', 'Mega Aggron'),
       '0319M': ('sharpedo-mega', '0001', 'Mega Sharpedo'), '0373M': ('salamence-mega', '0001', 'Mega Salamence'),
       '0376M': ('metagross-mega', '0001', 'Mega Metagross'), '0382P': ('kyogre-primal', '0001', 'Primal Kyogre'),
       '0383P': ('groudon-primal', '0001', 'Primal Groudon')}


def ident_for(species, key, name):
    base = species[species[key]['megaBase']]['name'].lower().replace(' ', '-').replace('.', '').replace("'", '')
    suf = '-x' if name.endswith(' X') else '-y' if name.endswith(' Y') else ''
    for cand in (f'{base}-mega{suf}', f'{base}-curly-mega', f'{base}-male-mega'):
        if cand in pid_of:
            return cand
    return None


def mul_of(mpid, bpid):
    mb, bb = st(mpid), st(bpid)
    return [round(mb[0] / bb[0], 3), round(mb[1] / bb[1], 3), round(mb[3] / bb[3], 3), round(mb[2] / bb[2], 3), round(mb[4] / bb[4], 3)]


def ability_of(pid):
    a = sorted(pab.get(pid, []))
    return [x for _, x in a][:1]


def apply(species, log=print):
    # ---------------------------------------------------------------- existing Megas: real Mega ability, real types
    fixed = []
    for k, v in species.items():
        if not v.get('megaBase') or k in NEW:
            continue
        idn = ident_for(species, k, v['name'])
        if not idn:
            log('no pokeapi entry for', k, v['name']); continue
        pid = pid_of[idn]
        # newer PokeAPI data lists some Megas (Legends Z-A) before their abilities: keep the current ones then
        v['ab'] = ability_of(pid) or v.get('ab', [])
        v['types'] = [t for _, t in sorted(types[pid])] or v['types']
        fixed.append((v['name'], v['ab']))

    # ---------------------------------------------------------------- new DX Megas
    for key, (idn, sub, name) in NEW.items():
        base = key[:4]
        B = species[base]
        pid = pid_of[idn]
        bpid = str(int(base))
        e = {kk: B[kk] for kk in ('learn', 'tm', 'exp', 'size', 'shadow', 'regen', 'asleep', 'speed', 'move') if kk in B}
        e.update({'name': name, 'types': [t for _, t in sorted(types[pid])], 'ab': ability_of(pid), 'recruit': 0,
                  'b': st(pid), 'red': 0, 'megaBase': base, 'mul': mul_of(pid, bpid)})
        if B.get('legend'):
            e['legend'] = 1
        species[key] = e
    log('megas: fixed abilities of', len(fixed), '- new megas:', len(NEW))
    return species


def main():
    path = os.path.join(common.DATA, 'species.json')
    save_ascii(path, apply(common.load_json(path)))


if __name__ == '__main__':
    main()
