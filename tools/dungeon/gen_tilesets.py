#!/usr/bin/env python3
"""Dungeon floor/wall/water tilesets for the Godot game: assets/tiles/* + data/tilesets.json.

  r00..r63   Red Rescue Team tilesets from the GBA ROM (10 blocks of 24x24 per row, transparent background,
             animated colours shown with the first colour of their animation), rules = bNNcex
  t14        Red tileset 14 with the placeholder colours of bNNpal for the animated slots (the old
             remake's default set; the game falls back to it) + hd_t14 (xBRZ 3x, block by block)
  hd_rNN     xBRZ 3x of r01 r05 r08 r20 r22 r26 r32 r33 (the sets that had an HD copy in the old remake)
  s000..s169 Explorers of Sky tilesets from DUNGEON/dungeon.bin (RGB, 10 chunks per row), rules = DMA
"""
import os, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import common
import dtiles as D
import eos_tiles as ET

OUT = os.path.join(common.ASSETS, 'tiles')
HD_RED = [1, 5, 8, 20, 22, 26, 32, 33]
PLACEHOLDER_ART = {14}      # tilesets whose game art (tNN) bakes bNNpal's placeholder colours for slots 160..191
HD_K = 3


def webp(img, path):
    img.save(common.p(path), 'WEBP', lossless=True, quality=100, method=4)


def xbrz_tiles(img, tile=24, k=HD_K, pad=2):
    """Scale each block on its own (padded with its own edge) so neighbours in the sheet don't bleed."""
    a = np.array(img.convert('RGBA')); H, W = a.shape[:2]
    out = np.zeros((H * k, W * k, 4), np.uint8)
    for y in range(0, H, tile):
        for x in range(0, W, tile):
            t = a[y:y + tile, x:x + tile]
            if not t[..., 3].any():
                continue
            pp = np.pad(t, ((pad, pad), (pad, pad), (0, 0)), mode='edge')
            s = np.array(common.xbrz_scale(Image.fromarray(pp, 'RGBA'), k))
            s = s[pad * k:pad * k + t.shape[0] * k, pad * k:pad * k + t.shape[1] * k]
            out[y * k:y * k + s.shape[0], x * k:x * k + s.shape[1]] = s
    return Image.fromarray(out, 'RGBA')


def main():
    common.need(os.path.join(common.PMDRED, 'baserom.gba'), 'Red ROM (pmd-red/baserom.gba)')
    dbin = None if common.RED_ONLY else common.need(os.path.join(common.EOS, 'fs', 'DUNGEON', 'dungeon.bin'), 'Explorers of Sky DUNGEON/dungeon.bin')
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    # ---- Red
    for ts in range(64):
        d = D.load(ts)
        idx = D.sheet(d)
        k = 'r%02d' % ts
        img = Image.fromarray(D.to_rgba(d, idx, opaque_zero=False, pal=D.palette(d)), 'RGBA')
        webp(img, os.path.join(OUT, k + '.webp'))
        e = {'img': k + '.webp', 'rules': D.rules(d), 'cols': 10}
        if ts in HD_RED:
            webp(common.xbrz_scale(img, HD_K), os.path.join(OUT, 'hd_' + k + '.webp'))
            e['hd'] = 'hd_' + k + '.webp'
        if ts == 14:
            t14 = Image.fromarray(D.to_rgba(d, idx, opaque_zero=False, pal=D.palette(d, False)), 'RGBA')
            t14.save(common.p(os.path.join(OUT, 't14.png')), optimize=True)
            webp(xbrz_tiles(t14), os.path.join(OUT, 'hd_t14.webp'))
            meta['t14'] = {'img': 't14.png', 'rules': D.rules(d), 'cols': 10, 'hd': 'hd_t14.webp'}
        meta[k] = e
    print('red tilesets 64 (+t14, %d hd)' % len(HD_RED), flush=True)
    # ---- Explorers of Sky
    n_eos = 0 if dbin is None else ET.N_TILESETS
    E = ET.pack_entries(open(dbin, 'rb').read()) if dbin else None
    for t in range(n_eos):
        img, rules = ET.render(E, t)
        k = 's%03d' % t
        Image.fromarray(img, 'RGB').save(common.p(os.path.join(OUT, k + '.png')), optimize=True)
        meta[k] = {'img': k + '.png', 'cols': 10, 'rules': rules}
    print('eos tilesets', n_eos, flush=True)
    order = ['t14'] + ['r%02d' % i for i in range(64)] + ['s%03d' % i for i in range(n_eos)]
    common.save_json(os.path.join(common.DATA, 'tilesets.json'), {k: meta[k] for k in order})


if __name__ == '__main__':
    main()
