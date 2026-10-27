#!/usr/bin/env python3
"""Extract PMD Red dungeon graphics from the ROM for the Godot remake.
Outputs to assets/dungeon/ and data/dungeon_gfx.json, data/dungeon_talk.json:
  - boss arena tilesets b64..b75 (bNNfon/cel/pal + emap0), 1x + xBRZ 3x HD (hd_arena_NN.webp) + palette-index map
  - palette-index sheets for the animated colours (bNNcanm) of tilesets 0..63 (tidx_rNN.png)
  - status icons (graphics/status + monster 'palet'), weather colour ramps (colvec), weather efbg animations
  - floor banner font (banfont/banrpal), floor map tiles (zmappat), dungeon talk lines (talkN/talkpN)
Move animations (assets/fx, data/fx.json, data/move_fx.json) are made elsewhere (tools/fx).
"""
import csv, os, re, sys, struct
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import common
import redrom as R, dtiles as D, zmap, efbg, gen_tilesets

# REF_COMPAT=1: write the old remake's 'base' colours for tilesets 0..63 (bNNpal placeholders), which do not
# match the colours baked into rNN.webp (see main())
REF_COMPAT = os.environ.get('REF_COMPAT') == '1'

OUT = os.path.join(common.ASSETS, 'dungeon') + os.sep
DEC = common.PMDRED + os.sep
hexc = lambda c: '#%02x%02x%02x' % tuple(int(v) for v in c[:3])


def idx_map(idx, alpha_zero=True):
    """palette index -> R = 0 (static) or 1 + animated colour slot (index 160..191); A = 0 where the art
    sheet is transparent (colour 0 of a palette row), so blended blocks composite like the art."""
    m = np.where(idx >= 160, idx - 159, 0).astype(np.uint8)
    a = np.where((idx % 16 == 0) & alpha_zero, 0, 255).astype(np.uint8)
    z = np.zeros_like(m)
    return Image.fromarray(np.dstack([m, z, z, a]), 'RGBA')

def save_talk(talk):
    import json
    with open(common.p(os.path.join(common.DATA, 'dungeon_talk.json')), 'w', encoding='utf-8') as f:
        json.dump(talk, f, ensure_ascii=False, indent=0)


def main():
    common.need(os.path.join(common.PMDRED, 'baserom.gba'), 'Red ROM (pmd-red/baserom.gba)')
    os.makedirs(OUT, exist_ok=True)
    data = {'anim': {}, 'arenas': {}}
    # ---------------------------------------------------------------- tilesets: animated colours + index sheets
    for ts in range(76):
        d = D.load(ts)
        if ts >= 64 or (ts not in gen_tilesets.PLACEHOLDER_ART and not REF_COMPAT):
            # the palettes leave BG colours 160..191 as placeholders (magenta / green on arenas); the art bakes
            # the first colour of each animated slot instead, so the upscaled art's edges blend with the real
            # colours. The "base" colour (3rd field) must be the colour baked into the art the game draws, since
            # dungeon_palette.gdshader adds (current - base) to it. (t14 bakes the placeholders: keep them.)
            for i, a in enumerate(d['anim']):
                if a['colors']:
                    d['pal'][160 + i] = a['colors'][0]
        an = []
        for i, a in enumerate(d['anim']):
            an.append([int(a['dur']), [hexc(c) for c in a['colors']], hexc(d['pal'][160 + i])])
        data['anim'][str(ts)] = an
        if ts < 64:
            idx = D.sheet(d)
            if (idx >= 160).any():
                idx_map(idx).save(OUT + 'tidx_r%02d.png' % ts)
        else:
            e = d['emap']
            idx = np.zeros((576, 576), np.int32)
            for y in range(24):
                for x in range(24):
                    idx[y * 24:y * 24 + 24, x * 24:x * 24 + 24] = D.render_block(d, e[y * 24 + x])
            rgba = D.to_rgba(d, idx)
            Image.fromarray(rgba).save(OUT + 'arena_%02d.png' % ts)
            hd = common.xbrz_scale(Image.fromarray(rgba), 3)
            hd.save(OUT + 'hd_arena_%02d.webp' % ts, lossless=True, quality=100)
            has_anim = bool((idx >= 160).any())
            if has_anim:
                idx_map(idx, False).save(OUT + 'aidx_%02d.png' % ts)
            data['arenas'][str(ts)] = {'img': 'arena_%02d.png' % ts, 'hd': 'hd_arena_%02d.webp' % ts, 'size': 24,
                                       'idx': ('aidx_%02d.png' % ts) if has_anim else ''}

    # ---------------------------------------------------------------- status icons (dungeon_pokemon_sprites.c)
    GFX = [None, ('sleepless', 1, 1, 14), ('burned', 2, 2, 7), ('poisoned', 2, 2, 16), ('frozen', 4, 4, 6), ('confused', 4, 2, 4),
           ('whiffer', 2, 2, 9), ('taunted', 2, 2, 8), ('lowhp', 1, 2, 8), ('shield', 2, 2, 13), ('statdown', 2, 2, 10),
           ('sword', 2, 2, 13), ('blinker', 1, 1, 14), ('cross_eyed', 2, 2, 10), ('eyedrops', 1, 1, 14), ('muzzled', 2, 2, 8),
           ('sleep', 2, 2, 10)]
    SPR = [(0, 0), (1, 0), (2, 0), (3, 11), (3, 7), (5, 0), (6, 0), (7, 0), (8, 0), (9, 0), (9, 4), (9, 3), (9, 10), (9, 5), (8, 0),
           (3, 6), (8, 3), (11, 0), (6, 10), (11, 5), (11, 4), (12, 0), (13, 0), (14, 0), (15, 0), (9, 7), (14, 4), (16, 4), (10, 3), (4, 0)]
    # SPR[k] for status sprite id k-1 (index 0 = none), as sStatusSpritesInfo
    palet = R.rgb_list(R.Archive(0x8510000).raw('palet'), 16 * 13)
    cols = []
    st = {}
    x = 0
    for k in range(1, 30):
        g, pal = SPR[k]
        name, tw, th, n = GFX[g]
        im = np.array(Image.open(DEC + 'graphics/status/%s.png' % name))
        w, h = tw * 8, th * 8
        strip = np.zeros((h * n, w, 4), np.uint8)
        for f in range(n):
            fr = im[f * h:(f + 1) * h, :w]
            for yy in range(h):
                for xx in range(w):
                    c = fr[yy, xx] & 0xF
                    if c:
                        strip[f * h + yy, xx] = (*palet[pal * 16 + c], 255)
        cols.append((x, strip))
        st[str(k - 1)] = {'x': x, 'w': w, 'h': h, 'n': n, 'gfx': name}
        x += w
    H = max(s.shape[0] for _, s in cols)
    atlas = np.zeros((H, x, 4), np.uint8)
    for xx, s in cols:
        atlas[:s.shape[0], xx:xx + s.shape[1]] = s
    Image.fromarray(atlas).save(OUT + 'status_icons.png')
    data['status'] = st

    # ---------------------------------------------------------------- weather colour ramps (colvec)
    a = R.dungeon()
    cv = a.raw('colvec')
    lut = np.zeros((8, 256, 4), np.uint8)
    for wi in range(8):
        c = R.rgb_list(cv + wi * 256 * 4, 256)
        lut[wi, :, :3] = np.array(c, np.uint8)
        lut[wi, :, 3] = 255
    Image.fromarray(lut).save(OUT + 'colvec.png')

    # ---------------------------------------------------------------- weather efbg (weather.c sub_8042818 -> effect_data.c)
    # weather index: 0 clear 1 sunny 2 sandstorm 3 cloudy 4 rain 5 hail 6 fog 7 snow
    WEFF = {'2': '006', '4': '004', '5': '002', '7': '007'}
    data['weather'] = {}
    for wi, e in WEFF.items():
        fr = efbg.render(e)
        n = len(fr); cols_n = 8; rows = (n + cols_n - 1) // cols_n
        sheet = np.zeros((rows * 160, cols_n * 240, 4), np.uint8)
        for i, f in enumerate(fr):
            sheet[(i // cols_n) * 160:(i // cols_n + 1) * 160, (i % cols_n) * 240:(i % cols_n + 1) * 240] = f['img']
        Image.fromarray(sheet).save(OUT + 'efbg%s.png' % e)
        data['weather'][wi] = {'sheet': 'efbg%s.png' % e, 'cols': cols_n, 'n': n,
                               'frames': [[f['dur'], f['fade'], f['speed']] for f in fr]}

    # ---------------------------------------------------------------- floor banner font (dungeon_name_banner.c)
    bo = a.raw('banfont')
    arr = R.off(R.u32(bo)); n = R.u32(bo + 4)
    bpal = R.rgb_list(a.raw('banrpal'), 16)
    glyphs = {}
    gimg = np.zeros((((n + 15) // 16) * 24, 16 * 24, 4), np.uint8)
    for i in range(n):
        p, ch, w = struct.unpack_from('<IHB', R.rom(), arr + i * 8)
        src = R.off(p)
        nib = []
        for b in R.rom()[src:src + 288]:
            nib += [(b >> 4) & 0xF, b & 0xF]
        out = []; si = 0
        while len(out) < 576:
            c = nib[si]; si += 1
            r6 = c & 7
            if c & 8:
                v = nib[si]; si += 1
                for _ in range(r6):
                    out.append(v)
                    if len(out) >= 576: break
            else:
                for _ in range(r6):
                    out.append(nib[si]); si += 1
                    if len(out) >= 576: break
        px = np.array(out[:576]).reshape(24, 24)
        gx, gy = (i % 16) * 24, (i // 16) * 24
        for yy in range(24):
            for xx in range(24):
                if px[yy, xx]:
                    gimg[gy + yy, gx + xx] = (*bpal[px[yy, xx]], 255)
        glyphs[str(ch)] = [i, w]
    Image.fromarray(gimg).save(OUT + 'banfont.png')
    data['banner'] = {'glyphs': glyphs, 'cols': 16}

    # ---------------------------------------------------------------- floor map tiles (zmappat)
    cells, zpal = zmap.load()
    fontpal = R.rgb_list(R.Archive(0x8300500).raw('fontpal'), 16)
    zpal = list(zpal); zpal[14] = fontpal[1]          # LoadDungeonMapPalette: colour 14 = gFontPalette[1]
    mimg = np.zeros((12 * 4, 16 * 4, 4), np.uint8)
    for t in range(192):
        c = cells[(t, 0)][:4, :4]
        gx, gy = (t % 16) * 4, (t // 16) * 4
        for yy in range(4):
            for xx in range(4):
                v = c[yy, xx]
                if v > 0:
                    mimg[gy + yy, gx + xx] = (*zpal[v], 255)
    Image.fromarray(mimg).save(OUT + 'zmappat.png')

    common.save_json(os.path.join(common.DATA, 'dungeon_gfx.json'), data)

    # ---------------------------------------------------------------- talk lines (talkN / talkpN, sub_806A3D4)
    names = {}
    for l in open(DEC + 'include/constants/monster.h'):
        m = re.match(r'#define MONSTER_(\w+) (\d+)', l)
        if m:
            names[int(m.group(2))] = m.group(1)
    norm = lambda s: re.sub(r'[^A-Z0-9]', '', s.upper().replace('♀', 'F').replace('♂', 'M'))
    by_name = {}           # species key = national dex number '0001' (PokeAPI pokemon_species.csv)
    with open(os.path.join(common.POKEAPI_CSV, 'pokemon_species.csv'), encoding='utf-8') as f:
        for r in csv.DictReader(f):
            by_name.setdefault(norm(r['identifier']), '%04d' % int(r['id']))
    def clean(s):
        s = s.replace('\r', '\n')
        s = re.sub(r'~([0-9a-fA-F]{2})', lambda m: bytes([int(m.group(1), 16)]).decode('latin1'), s)
        return s.replace('\x81\x9b', 'é')
    talk = {'mon': {}, 'partner': {}, 'special': {}}
    for kind, prefix in (('mon', 'talk'), ('partner', 'talkp')):
        for fi in range(43):
            fn = '%s%d' % (prefix, fi)
            if fn not in a.files: continue
            o = a.raw(fn)
            for s in range(10):
                rid = fi * 10 + s
                strs = []
                for k in range(4):
                    p = R.u32(o + (s * 4 + k) * 4)
                    if not (0x08000000 <= p < 0x0A000000):
                        strs = None; break
                    q = R.off(p)
                    strs.append(clean(R.rom()[q:R.rom().index(b'\0', q)].decode('latin1')))
                if not strs: continue
                if rid in (0x1A4, 0x1A5):
                    talk['special'][kind + ('_client' if rid == 0x1A4 else '_base')] = strs
                    continue
                nm = names.get(rid, '')
                key = by_name.get(norm(nm.replace('_', '')))
                if key and key not in talk[kind]:
                    talk[kind][key] = strs
    save_talk(talk)
    print('talk', len(talk['mon']), len(talk['partner']), list(talk['special']))


if __name__ == '__main__':
    main()
