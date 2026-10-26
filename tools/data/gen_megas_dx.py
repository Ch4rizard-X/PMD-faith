#!/usr/bin/env python3
"""Rescue Team DX's Mega Evolutions (Empowerment Seed / Awakened).
- adds the DX Megas the game was missing (stats, types, ability from PokeAPI; PMD stats = base form x Mega ratios)
- fixes every Mega's ability to its real Mega ability (PokeAPI)
- sprites: SpriteCollab Mega sheets where they exist (assets/sp/mega_KEY.png), else the base form's sprite;
  Mega portraits from SpriteCollab (assets/sp/pKEY.png)
Writes data/species.json, data/sprites.json."""
import csv, json, os, re
from PIL import Image

G = '/tmp/claude-0/pmd1/game/'
SC = '/tmp/claude-0/scnew/repo/'
PA = '/tmp/claude-0/pokeapi/data/v2/csv/'
J = lambda p: json.load(open(p))
species = J(G + 'data/species.json'); sprites = J(G + 'data/sprites.json')

pid_of = {r['identifier']: r['id'] for r in csv.DictReader(open(PA + 'pokemon.csv'))}
stats = {}
for r in csv.DictReader(open(PA + 'pokemon_stats.csv')):
    stats.setdefault(r['pokemon_id'], {})[r['stat_id']] = int(r['base_stat'])
tname = {r['id']: r['identifier'].capitalize() for r in csv.DictReader(open(PA + 'types.csv'))}
types = {}
for r in csv.DictReader(open(PA + 'pokemon_types.csv')):
    types.setdefault(r['pokemon_id'], []).append((int(r['slot']), tname[r['type_id']]))
abil = {r['id']: r['identifier'] for r in csv.DictReader(open(PA + 'abilities.csv'))}
pab = {}
for r in csv.DictReader(open(PA + 'pokemon_abilities.csv')):
    pab.setdefault(r['pokemon_id'], []).append((int(r['slot']), abil[r['ability_id']]))
dex_name = {r['id']: r['identifier'] for r in csv.DictReader(open(PA + 'pokemon_species.csv'))}

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


def ident_for(key, name):
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


# ---------------------------------------------------------------- existing Megas: real Mega ability, real types
fixed = []
for k, v in species.items():
    if not v.get('megaBase') or k in NEW:
        continue
    idn = ident_for(k, v['name'])
    if not idn:
        print('no pokeapi entry for', k, v['name']); continue
    pid = pid_of[idn]
    v['ab'] = ability_of(pid)
    v['types'] = [t for _, t in sorted(types[pid])]
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

# ---------------------------------------------------------------- sprites / portraits
WANT = ['Walk', 'Attack', 'Hurt', 'Idle', 'Sleep', 'Shoot', 'Charge', 'Hop', 'Strike', 'Double', 'Rotate', 'Swing']


def anim_data(d):
    xml = open(d + 'AnimData.xml').read()
    anims = {}
    for blk in re.findall(r'<Anim>(.*?)</Anim>', xml, re.S):
        nm = re.search(r'<Name>(\w+)</Name>', blk).group(1)
        cp = re.search(r'<CopyOf>(\w+)</CopyOf>', blk)
        if cp:
            anims[nm] = {'copy': cp.group(1)}; continue
        w = int(re.search(r'<FrameWidth>(\d+)', blk).group(1)); h = int(re.search(r'<FrameHeight>(\d+)', blk).group(1))
        anims[nm] = {'w': w, 'h': h, 'dur': [int(x) for x in re.findall(r'<Duration>(\d+)</Duration>', blk)]}
    return anims


def build_sheet(key, d):
    A = anim_data(d)
    parts = []; man = {}; y = 0
    for an in WANT:
        a = A.get(an); src = an
        while a and 'copy' in a:
            src = a['copy']; a = A.get(src)
        if not a or not os.path.exists(d + f'{src}-Anim.png'):
            continue
        im = Image.open(d + f'{src}-Anim.png').convert('RGBA')
        parts.append((im, y))
        man[an] = {'x': 0, 'y': y, 'w': a['w'], 'h': a['h'], 'dur': a['dur'], 'rows': max(1, im.height // a['h'])}
        y += im.height
    W = max(im.width for im, _ in parts)
    sheet = Image.new('RGBA', (W, y))
    for im, yy in parts:
        sheet.paste(im, (0, yy))
    sheet.save(G + f'assets/sp/mega_{key}.png', optimize=True)
    return man


def build_portraits(key, d):
    if not os.path.isdir(d):
        return {}
    ems = sorted(f[:-4] for f in os.listdir(d) if f.endswith('.png') and '^' not in f)
    if not ems:
        return {}
    cols = 6
    rows = (len(ems) + cols - 1) // cols
    sheet = Image.new('RGBA', (40 * min(cols, len(ems)), 40 * rows))
    por = {}
    for i, em in enumerate(ems):
        im = Image.open(d + em + '.png').convert('RGBA').resize((40, 40))
        x, yy = (i % cols) * 40, (i // cols) * 40
        sheet.paste(im, (x, yy))
        por[em] = [x, yy, 40, 40, f'p{key}.png']
    sheet.save(G + f'assets/sp/p{key}.png', optimize=True)
    return por


own = []
for key, (idn, sub, name) in NEW.items():
    base = key[:4]
    bman = sprites.get(base, {})
    sd = SC + f'sprite/{base}/{sub}/'
    por = build_portraits(key, SC + f'portrait/{base}/{sub}/') or bman.get('por', {})
    if os.path.exists(sd + 'AnimData.xml') and os.path.exists(sd + 'Idle-Anim.png') and os.path.exists(sd + 'Walk-Anim.png'):
        anims = build_sheet(key, sd)
        sprites[key] = {'sheet': f'mega_{key}.png', 'sh': bman.get('sh', 1), 'shd': bman.get('shd'), 'anims': anims, 'por': por}
        own.append(name)
    else:
        e = json.loads(json.dumps(bman))
        e['por'] = por
        e['base_sprite'] = 1          # no Mega sheet yet: the base form's sprite (drawn with the Awakened glow)
        sprites[key] = e

json.dump(species, open(G + 'data/species.json', 'w'), separators=(',', ':'))
json.dump(sprites, open(G + 'data/sprites.json', 'w'), separators=(',', ':'))
print('fixed abilities:', fixed)
print('new megas:', len(NEW), 'own sprites:', own)
