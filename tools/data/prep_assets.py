#!/usr/bin/env python3
"""Copy sprites, tiles and icons from the old remake into the Godot project, with JSON indexes."""
import json, os, shutil, base64, io
from PIL import Image
R = '/tmp/claude-0/pmd1/dump'
W = '/tmp/claude-0/rt/app/src/main/assets/www/'
G = '/tmp/claude-0/pmd1/game/'
J = lambda p: json.load(open(p))
os.makedirs(G + 'assets/sp', exist_ok=True); os.makedirs(G + 'assets/tiles', exist_ok=True); os.makedirs(G + 'assets/ui', exist_ok=True)

# ---- Pokemon sprite sheets
MAN = J(R + '/MAN.json'); MF = J(R + '/MANIFEST.json')
sheets = MF['sheets']
used = set()
out = {}
for k, m in MAN.items():
    e = {'sheet': sheets[m['sheet']].split('/')[-1], 'sh': m.get('sh', 1), 'shd': m.get('shd'), 'anims': {}, 'por': m.get('portraits', {})}
    used.add(m['sheet'])
    for an, a in m['anims'].items():
        aa = {'x': a.get('x', 0), 'y': a['y'], 'w': a['w'], 'h': a['h'], 'dur': a['dur'], 'rows': a['rows']}
        if a.get('s') is not None:
            aa['s'] = sheets[a['s']].split('/')[-1]; used.add(a['s'])
        e['anims'][an] = aa
    out[k] = e
for i in used:
    src = W + sheets[i]; dst = G + 'assets/sp/' + sheets[i].split('/')[-1]
    if not os.path.exists(dst): shutil.copyfile(src, dst)
json.dump(out, open(G + 'data/sprites.json', 'w'), separators=(',', ':'))
print('sprite sheets', len(used))

# ---- shadow markers
MK = J(R + '/MARK.json')
for k, url in MK['img'].items():
    open(G + f'assets/ui/mark_{k}.png', 'wb').write(base64.b64decode(url.split(',', 1)[1]))
json.dump({'off': MK['off'], 'size': MK['size']}, open(G + 'data/marks.json', 'w'), separators=(',', ':'))

# ---- tilesets: all Red sets (rules) + images; HD versions where they exist
TS = J(R + '/TILESETS.json')
tiles = {}
for k, t in TS.items():
    if not (k.startswith('r') or k == 't14'): continue
    src = W + t['img']; name = t['img'].split('/')[-1]
    shutil.copyfile(src, G + 'assets/tiles/' + name)
    e = {'img': name, 'rules': t['rules'], 'cols': t.get('cols') or 10}
    hd = W + 'assets/hd/tiles/' + name.rsplit('.', 1)[0] + '.webp'
    if os.path.exists(hd):
        shutil.copyfile(hd, G + 'assets/tiles/hd_' + name.rsplit('.', 1)[0] + '.webp'); e['hd'] = 'hd_' + name.rsplit('.', 1)[0] + '.webp'
    tiles[k] = e
json.dump(tiles, open(G + 'data/tilesets.json', 'w'), separators=(',', ':'))
print('tilesets', len(tiles), 'hd', sum(1 for t in tiles.values() if 'hd' in t))

# ---- item icons -> one atlas
IC = J(R + '/ICON.json')
ids = sorted(IC.keys()); cols = 16
atlas = Image.new('RGBA', (cols * 16, ((len(ids) + cols - 1) // cols) * 16))
idx = {}
for n, k in enumerate(ids):
    v = IC[k]
    if not isinstance(v, dict) or 'url' not in v: continue
    if v['url'].startswith('data:'): im = Image.open(io.BytesIO(base64.b64decode(v['url'].split(',', 1)[1]))).convert('RGBA')
    else: im = Image.open(W + v['url']).convert('RGBA').crop((v.get('x', 0), v.get('y', 0), v.get('x', 0) + v.get('sz', 16), v.get('y', 0) + v.get('sz', 16)))
    sz = v.get('sz', 16)
    if im.size != (16, 16): im = im.resize((16, 16), Image.NEAREST)
    atlas.paste(im, ((n % cols) * 16, (n // cols) * 16)); idx[k] = [(n % cols) * 16, (n // cols) * 16]
atlas.save(G + 'assets/ui/items.png')
json.dump(idx, open(G + 'data/item_icons.json', 'w'), separators=(',', ':'))
print('item icons', len(idx))

# ---- misc UI art
for f in ['assets/packs/dmg_blue.png', 'assets/packs/dmg_red.png', 'assets/packs/cursors.png', 'assets/tiles/stairs.png', 'assets/fonts/pmd_red_text.ttf',
          'assets/portraits_emo.png', 'assets/title/logo_transparent.png', 'assets/title/menu_artwork_1.png', 'assets/title/menu_artwork_2.png', 'assets/title/menu_artwork_3.png']:
    if os.path.exists(W + f): shutil.copyfile(W + f, G + 'assets/ui/' + f.split('/')[-1])
print('done')
