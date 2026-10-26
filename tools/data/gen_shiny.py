#!/usr/bin/env python3
"""Shiny colour tables from SpriteCollab: normal vs shiny Idle sprite (and Normal portrait), pixel by pixel.
data/shiny.json: {species: {"s": [[r,g,b, r,g,b], ...], "p": [...]}} (most used colours first, max 48)."""
import json, os
from collections import Counter
from PIL import Image
G = '/tmp/claude-0/pmd1/game/'; SC = '/tmp/claude-0/scnew/repo/'
sprites = json.load(open(G + 'data/sprites.json'))
MAXC = 48

def table(a, b):
    a = Image.open(a).convert('RGBA'); b = Image.open(b).convert('RGBA')
    if a.size != b.size:
        return None
    pairs = Counter()
    for p, q in zip(a.get_flattened_data(), b.get_flattened_data()):
        if p[3] > 0 and q[3] > 0:
            pairs[(p[:3], q[:3])] += 1
    best = {}
    for (s, d), n in pairs.most_common():
        if s not in best:
            best[s] = (d, n)
    rows = [list(s) + list(d) for s, (d, n) in sorted(best.items(), key=lambda kv: -kv[1][1]) if s != d]
    return rows[:MAXC]

out = {}; ns = np_ = 0
for sp in sorted(k for k in sprites if len(k) == 4 and k.isdigit()):
    e = {}
    a, b = SC + f'sprite/{sp}/Idle-Anim.png', SC + f'sprite/{sp}/0000/0001/Idle-Anim.png'
    if os.path.exists(a) and os.path.exists(b):
        t = table(a, b)
        if t: e['s'] = t; ns += 1
    a, b = SC + f'portrait/{sp}/Normal.png', SC + f'portrait/{sp}/0000/0001/Normal.png'
    if os.path.exists(a) and os.path.exists(b):
        t = table(a, b)
        if t: e['p'] = t; np_ += 1
    if e:
        out[sp] = e
json.dump(out, open(G + 'data/shiny.json', 'w'), separators=(',', ':'))
print('species with shiny sprite', ns, 'portrait', np_, 'of', len([k for k in sprites if len(k) == 4]))
print('max colours', max(len(v.get('s', [])) for v in out.values()), max(len(v.get('p', [])) for v in out.values()))
print('size KB', os.path.getsize(G + 'data/shiny.json') // 1024)
