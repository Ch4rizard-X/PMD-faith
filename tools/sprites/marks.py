"""Red's dungeon shadow markers (the ellipse under every Pokémon: black for enemies, gold for the team, rippling
blue in water), straight from your Red ROM, plus Red's shadow size per species.

  tiles    dungeon archive "etcfont" (loaded at OBJ tile 0x200, sub_803DF60) and the 3-frame water animation
           "etcfonta" (copied to OBJ tile 0x220 every 4 frames, sub_803ECE0)
  colours  OBJ palette 0 = first 16 colours of the monster archive's "palet" (OpenDungeonPaletteFile)
  shapes   gUnknown_80F621C (shape/size/tile) and offsets gUnknown_80F61EC in src/dungeon_vram.c
  sizes    shadowSize in data/monster/monster_data.json of the decomp

Writes data/marks.json {"off": {...}, "size": {species: 0..2}} and assets/ui/mark_<side>_<size>.png."""
import json
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

ROM = os.path.join(common.PMDRED, 'baserom.gba')
SIDES = ('enemy', 'team')
# gUnknown_80F621C / gUnknown_80F61EC: [side][index] -> (width, height, first tile), (x, y); 0..2 small/medium/large,
# 3 = water (the same for indices 3..5)
SHAPES = {
    'enemy': [(8, 8, 0x200), (16, 8, 0x201), (32, 8, 0x203), (32, 8, 0x223)],
    'team': [(8, 8, 0x207), (16, 8, 0x208), (32, 16, 0x20A), (32, 16, 0x22A)],
}
OFFS = {
    'enemy': [(-4, -4), (-8, -4), (-16, -4), (-16, -4)],
    'team': [(-4, -4), (-8, -4), (-16, -8), (-16, -8)],
}
NAMES = ['small', 'medium', 'large', 'water']


class Rom:
    def __init__(self):
        self.b = open(common.need(ROM, 'pmd-red baserom.gba (your Red ROM)'), 'rb').read()

    def u32(self, o):
        return struct.unpack_from('<I', self.b, o)[0]

    def archive_with(self, fname):
        """{name: offset} of the pksdir archive that holds fname."""
        i = 0
        while True:
            i = self.b.find(b'pksdir0', i)
            if i < 0:
                raise SystemExit(f'no archive with {fname} in the ROM')
            try:
                n, t = self.u32(i + 8), self.u32(i + 12) - 0x08000000
                files = {}
                for k in range(n):
                    p = self.u32(t + k * 8) - 0x08000000
                    name = self.b[p:self.b.index(b'\0', p)].decode('latin1')
                    files[name] = self.u32(t + k * 8 + 4) - 0x08000000
                if fname in files:
                    return files
            except (struct.error, ValueError, IndexError, UnicodeDecodeError):
                pass
            i += 4

    def data(self, files, name):
        o = files[name]
        if self.b[o:o + 4] in (b'SIRO', b'SIR0'):
            return self.u32(o + 4) - 0x08000000
        return o


def tile(b, o):
    t = b[o:o + 32]
    return np.array([[(t[y * 4 + x // 2] >> (4 * (x & 1))) & 15 for x in range(8)] for y in range(8)], np.uint8)


def obj(b, base, first, w, h):
    """1D-mapped OBJ of w x h pixels starting at tile `first` (tiles relative to `base` = tile 0x200 or 0x220)."""
    tw = w // 8
    rows = []
    for ty in range(h // 8):
        rows.append(np.hstack([tile(b, base + (first + ty * tw + tx) * 32) for tx in range(tw)]))
    return np.vstack(rows)


def to_rgba(idx, pal):
    out = np.zeros(idx.shape + (4,), np.uint8)
    for i in range(1, 16):
        out[idx == i] = list(pal[i]) + [255]
    return out


def red_sizes(keys):
    """Red's shadow size per species key (national dex; Munchlax by name)."""
    d = os.path.join(common.PMDRED, 'data', 'monster')
    mons = common.load_json(os.path.join(d, 'monster_data.json'))
    names = dict(re.findall(r'^(MonsterName\w+):\s*\n\.string "([^"\\]*)', open(os.path.join(d, 'monster_names.s'), encoding='utf-8').read(), re.M))
    sp_path = os.environ.get('SPRITES_SPECIES') or os.path.join(common.DATA, 'species.json')
    by_name = {}
    for k, v in common.load_json(sp_path).items():
        if k.isdigit():
            by_name.setdefault(v.get('name', ''), k)
    size = {}
    for m in mons:
        dex = m['dexInternal'][0]
        if 1 <= dex <= 386:
            k = '%04d' % dex
        else:
            k = by_name.get(names.get(m['name'], ''))
        if k and k in keys and k not in size:
            size[k] = m['shadowSize']
    return dict(sorted(size.items()))


def build(keys):
    r = Rom()
    dun = r.archive_with('etcfont')
    mon = r.archive_with('palet')
    pal = [tuple(r.b[mon['palet'] + i * 4:mon['palet'] + i * 4 + 3]) for i in range(16)]
    o = r.data(dun, 'etcfont')
    font = o + 4                                       # u32 tile count, then the tiles (OBJ tile 0x200 on)
    anim = r.data(dun, 'etcfonta')                     # 3 frames x 18 tiles (OBJ tile 0x220 on)
    off = {}
    ui = os.path.join(common.ASSETS, 'ui')
    os.makedirs(ui, exist_ok=True)
    for side in SIDES:
        for i, nm in enumerate(NAMES):
            w, h, t = SHAPES[side][i]
            off[f'{side}_{nm}'] = list(OFFS[side][i])
            if nm != 'water':
                img = to_rgba(obj(r.b, font, t - 0x200, w, h), pal)
                Image.fromarray(img, 'RGBA').save(os.path.join(ui, f'mark_{side}_{nm}.png'), optimize=True)
            else:
                for f in range(3):
                    img = to_rgba(obj(r.b, anim + f * 0x240, t - 0x220, w, h), pal)
                    Image.fromarray(img, 'RGBA').save(os.path.join(ui, f'mark_{side}_water{f + 1}.png'), optimize=True)
    order = [f'{s}_{n}' for s in SIDES for n in NAMES[:3]] + ['team_water', 'enemy_water']
    common.save_json(os.path.join(common.DATA, 'marks.json'),
                     {'off': {k: off[k] for k in order}, 'size': red_sizes(set(keys))})


if __name__ == '__main__':
    p = os.environ.get('SPRITES_SPECIES') or os.path.join(common.DATA, 'species.json')
    build(set(json.load(open(p, encoding='utf-8'))))
