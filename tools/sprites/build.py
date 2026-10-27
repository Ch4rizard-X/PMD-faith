#!/usr/bin/env python3
"""Pokémon sprites, portraits, shiny colours and shadow markers.

Inputs (all made by tools/fetch.py):
  SpriteCollab (sprite/<form>/AnimData.xml + *-Anim.png, portrait/<form>/*.png, shiny Idle sheets and Normal portraits)
  pmd-red decomp + your Red ROM (baserom.gba): the dungeon shadow-marker tiles and Red's shadow sizes
  data/species.json (made earlier in the pipeline) for the list of species keys

Outputs (game/):
  assets/sp/m<KEY>.png, m<KEY>_<n>.png   every animation of a species, packed (max 4096x4096 per sheet)
  assets/sp/p<KEY>.png                   its portraits (40x40, 6 per row)
  data/sprites.json                      the manifest the sprite loaders read
  data/shiny.json                        shiny colour tables (shaders/shiny.gdshader, Shiny.portrait)
  data/marks.json, assets/ui/mark_*.png  Red's team/enemy shadow markers

Run: python3 -I tools/sprites/build.py
Set SPRITES_SPECIES=<path to species.json> to build against another species list (development only).
"""
import hashlib
import json
import os
import sys
from collections import Counter
from multiprocessing import Pool

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402
import sclib  # noqa: E402
import marks  # noqa: E402
import credits  # noqa: E402

SP = os.path.join(common.ASSETS, 'sp')
MAXS = 4096                 # max sheet side (safe on every GPU the game targets)
POR = 40                    # portrait size
POR_COLS = 6
MAX_SHINY = 16              # colours the shiny shader handles
CORE_FALLBACK = [('Walk', 'Idle'), ('Attack', 'Walk'), ('Hurt', 'Idle')]   # missing core anims (as the reference)


def species_keys():
    path = os.environ.get('SPRITES_SPECIES') or os.path.join(common.DATA, 'species.json')
    common.need(path, 'species list (data/species.json; run the data step first)')
    return sorted(common.load_json(path))


# ------------------------------------------------------------------ PNG writing
def save_png(arr, path):
    """RGBA array -> PNG, palettised when it has at most 256 colours (lossless either way)."""
    a = arr.copy()
    a[a[..., 3] == 0] = 0
    flat = a.reshape(-1, 4).view(np.uint32).ravel()
    u, inv = np.unique(flat, return_inverse=True)
    if len(u) <= 256:
        cols = u.view(np.uint8).reshape(-1, 4)
        im = Image.fromarray(inv.reshape(a.shape[:2]).astype(np.uint8), 'P')
        im.putpalette(cols[:, :3].ravel().tolist())
        im.save(path, compress_level=6, transparency=bytes(cols[:, 3].tolist()))
    else:
        Image.fromarray(a, 'RGBA').save(path, compress_level=6)


def load_rgba(path):
    with Image.open(path) as im:
        a = np.asarray(im.convert('RGBA')).copy()
    a[a[..., 3] == 0] = 0
    return a


# ------------------------------------------------------------------ packing
def shelf_pack(blocks):
    """blocks: [(id, w, h)] -> [(W, H, {id: (x, y)})], each sheet at most MAXS x MAXS."""
    blocks = sorted(blocks, key=lambda b: (-b[2], -b[1], b[0]))
    sheets = []
    for bid, w, h in blocks:
        placed = False
        for sh in sheets:
            for shelf in sh['shelves']:          # [y, h, x cursor]
                if h <= shelf[1] and shelf[2] + w <= MAXS:
                    sh['pos'][bid] = (shelf[2], shelf[0])
                    shelf[2] += w
                    placed = True
                    break
            if placed:
                break
            if sh['top'] + h <= MAXS:
                sh['shelves'].append([sh['top'], h, w])
                sh['pos'][bid] = (0, sh['top'])
                sh['top'] += h
                placed = True
                break
        if not placed:
            sheets.append({'shelves': [[0, h, w]], 'top': h, 'pos': {bid: (0, 0)}})
    return [(max(s[2] for s in sh['shelves']), sh['top'], sh['pos']) for sh in sheets]


# ------------------------------------------------------------------ one species
def shadow_offsets(idle, fw, fh, rows):
    """Per-facing shadow point (the 'shd' of the reference): bottom of the first Idle frame and the centre of
    its lowest 5 pixel rows, relative to the frame centre (y minus 2, as the reference)."""
    out = []
    for r in range(8):
        rr = min(r, rows - 1)
        al = idle[rr * fh:(rr + 1) * fh, 0:fw, 3]
        ys, xs = np.nonzero(al)
        if not len(ys):
            out.append([0, 4])
            continue
        b = ys.max()
        m = ys > b - 5
        x = round((xs[m].min() + xs[m].max() + 1) / 2 - fw / 2)
        out.append([int(x), int(b + 1 - fh // 2 - 2)])
    return out


def build_portraits(key, form):
    ems = sclib.portrait_emotions(form)
    if not ems:
        return {}
    n = len(ems)
    cols = min(POR_COLS, n)
    sheet = np.zeros((POR * ((n + POR_COLS - 1) // POR_COLS), POR * cols, 4), np.uint8)
    por = {}
    name = f'p{key}.png'
    for i, em in enumerate(ems):
        a = load_rgba(os.path.join(sclib.portrait_dir(form), em + '.png'))
        if a.shape[:2] != (POR, POR):
            a = np.asarray(Image.fromarray(a).resize((POR, POR), Image.NEAREST))
        x, y = (i % POR_COLS) * POR, (i // POR_COLS) * POR
        sheet[y:y + POR, x:x + POR] = a
        por[em] = [x, y, POR, POR, name]
    save_png(sheet, os.path.join(SP, name))
    return por


def build_species(key):
    """Sheets + manifest entry for one key with its own SpriteCollab sheet. Returns (key, entry, report)."""
    form = sclib.form_path(key)
    d = sclib.sprite_dir(form)
    A, shadow_size = sclib.parse_animdata(os.path.join(d, 'AnimData.xml'))
    rep = {'skipped': []}
    srcs = {}        # anim name -> source anim name (after CopyOf)
    for nm in A:
        src = sclib.resolve(A, nm)
        if src is None:
            rep['skipped'].append((nm, 'bad CopyOf'))
        elif not os.path.exists(os.path.join(d, f'{src}-Anim.png')):
            rep['skipped'].append((nm, 'no png'))
        else:
            srcs[nm] = src
    # blocks: one per distinct source sheet (identical pixel content shares one block)
    blocks, meta, by_hash, alias = [], {}, {}, {}
    for src in sorted(set(srcs.values())):
        _, fw, fh, durs = A[src]
        img = load_rgba(os.path.join(d, f'{src}-Anim.png'))
        H, W = img.shape[:2]
        rows = 8 if H // fh >= 8 else 1
        n = min(W // fw, len(durs))
        if n == 0:
            rep['skipped'].append((src, 'empty'))
            continue
        img = img[:rows * fh, :n * fw]
        h = hashlib.sha1(img.tobytes() + bytes(str((fw, fh, rows)), 'ascii')).hexdigest()
        if h in by_hash:
            alias[src] = by_hash[h]
            meta[src] = dict(meta[by_hash[h]], dur=durs[:n])
            continue
        by_hash[h] = src
        cols = n
        if n * fw > MAXS:                       # wrap frames onto further lines ("cols")
            cols = MAXS // fw
        lines = (n + cols - 1) // cols
        bw, bh = cols * fw, lines * rows * fh
        if bw > MAXS or bh > MAXS:
            raise SystemExit(f'{key} {src}: block {bw}x{bh} does not fit in {MAXS}')
        meta[src] = {'img': img, 'w': fw, 'h': fh, 'rows': rows, 'n': n, 'cols': cols, 'dur': durs[:n]}
        blocks.append((src, bw, bh))
    sheets = shelf_pack([(b, w, h) for b, w, h in blocks])
    where = {}
    names = []
    for i, (W, H, pos) in enumerate(sheets):
        name = f'm{key}.png' if i == 0 else f'm{key}_{i + 1}.png'
        names.append(name)
        cur = np.zeros((H, W, 4), np.uint8)
        for src, (x, y) in pos.items():
            m = meta[src]
            fw, fh, rows = m['w'], m['h'], m['rows']
            for f in range(m['n']):
                cx, ln = f % m['cols'], f // m['cols']
                cur[y + ln * rows * fh:y + (ln + 1) * rows * fh, x + cx * fw:x + (cx + 1) * fw] = \
                    m['img'][:, f * fw:(f + 1) * fw]
            where[src] = (name, x, y)
        save_png(cur, os.path.join(SP, name))
    anims = {}
    for nm in A:                                 # AnimData order
        src = srcs.get(nm)
        if src is None or src not in meta:
            continue
        m = meta[src]
        name, x, y = where[alias.get(src, src)]
        e = {'x': x, 'y': y, 'w': m['w'], 'h': m['h'], 'dur': list(m['dur']), 'rows': m['rows']}
        if m['cols'] < m['n']:
            e['cols'] = m['cols']
        if name != names[0]:
            e['s'] = name
        anims[nm] = e
    for want, src in CORE_FALLBACK:
        if want not in anims and src in anims:
            anims[want] = dict(anims[src])
            rep.setdefault('fallback', []).append(f'{want}<-{src}')
    idle_src = srcs.get('Idle') or srcs.get('Walk')
    im = meta[idle_src]
    shd = shadow_offsets(im['img'], im['w'], im['h'], im['rows'])
    entry = {'sheet': names[0], 'sh': shadow_size, 'shd': shd, 'anims': anims, 'por': build_portraits(key, form)}
    return key, entry, rep


def worker(key):
    try:
        return build_species(key)
    except SystemExit:
        raise
    except Exception as ex:              # report and go on
        return key, None, {'error': repr(ex)}


# ------------------------------------------------------------------ shiny
def colour_table(a_path, b_path):
    a, b = load_rgba(a_path), load_rgba(b_path)
    if a.shape != b.shape:                              # shiny sheet drawn on another frame grid: unusable
        return None
    m = (a[..., 3] > 0) & (b[..., 3] > 0)
    pa = a[..., :3][m].astype(np.uint32)
    pb = b[..., :3][m].astype(np.uint32)
    ka = (pa[:, 0] << 16) | (pa[:, 1] << 8) | pa[:, 2]
    kb = (pb[:, 0] << 16) | (pb[:, 1] << 8) | pb[:, 2]
    pairs = Counter(zip(ka.tolist(), kb.tolist()))
    best = {}
    for (s, dd), n in pairs.most_common():          # most used shiny colour for each normal colour
        if s not in best:
            best[s] = (dd, n)
    rgb = lambda c: [c >> 16, (c >> 8) & 255, c & 255]
    rows = [rgb(s) + rgb(dd) for s, (dd, n) in sorted(best.items(), key=lambda kv: -kv[1][1]) if s != dd]
    return rows[:MAX_SHINY]


def idle_png(form, shiny):
    """Idle sheet of a form (or its shiny), following CopyOf."""
    d = sclib.sprite_dir(form)
    try:
        A, _ = sclib.parse_animdata(os.path.join(d, 'AnimData.xml'))
        src = sclib.resolve(A, 'Idle') or 'Idle'
    except (OSError, Exception):
        src = 'Idle'
    if shiny:
        sub = '0001' if '/' in form else os.path.join('0000', '0001')
        d = os.path.join(d, sub)
    p = os.path.join(d, f'{src}-Anim.png')
    return p if os.path.exists(p) else None


def build_shiny(sprites):
    out = {}
    for key in sorted(sprites):
        if sprites[key].get('base_sprite'):
            continue                                    # drawn with the base sheet -> base colours
        form = sclib.form_path(key)
        e = {}
        a, b = idle_png(form, False), idle_png(form, True)
        if a and b:
            t = colour_table(a, b)
            if t:
                e['s'] = t
        if key.isdigit():                               # portraits are looked up by the 4-digit species
            pa = os.path.join(sclib.portrait_dir(form), 'Normal.png')
            pb = os.path.join(sclib.portrait_dir(form), '0000', '0001', 'Normal.png')
            if os.path.exists(pa) and os.path.exists(pb):
                t = colour_table(pa, pb)
                if t:
                    e['p'] = t
        if e:
            out[key] = e
    return out


# ------------------------------------------------------------------ main
def main():
    common.need(os.path.join(sclib.SC, 'tracker.json'), 'SpriteCollab checkout')
    keys = species_keys()
    os.makedirs(SP, exist_ok=True)
    for f in os.listdir(SP):                           # start clean (this folder is ours alone)
        os.remove(os.path.join(SP, f))
    own, borrowed, missing = [], [], []
    for k in keys:
        form = sclib.form_path(k)
        if form and sclib.has_sheet(form):
            own.append(k)
        elif sclib.split_key(k)[1] and k[:4] in keys:
            borrowed.append(k)                         # Mega/Primal without a sheet yet: base form's sprite
        else:
            missing.append(k)
    sprites, report = {}, {}
    with Pool(max(1, min(4, os.cpu_count() or 1))) as pool:
        for i, (k, entry, rep) in enumerate(pool.imap_unordered(worker, own, chunksize=4)):
            if entry is not None:
                sprites[k] = entry
            if rep.get('error') or rep.get('fallback') or rep.get('skipped'):
                report[k] = rep
            if (i + 1) % 100 == 0:
                print(f'  sprites {i + 1}/{len(own)}', flush=True)
    for k in borrowed:
        base = sprites.get(k[:4])
        if base is None:
            missing.append(k)
            continue
        e = json.loads(json.dumps(base))
        e['por'] = build_portraits(k, sclib.form_path(k)) if sclib.form_path(k) else {}
        e['por'] = e['por'] or base['por']
        e['base_sprite'] = 1
        sprites[k] = e
    sprites = {k: sprites[k] for k in keys if k in sprites}
    common.save_json(os.path.join(common.DATA, 'sprites.json'), sprites)
    shiny = build_shiny(sprites)
    common.save_json(os.path.join(common.DATA, 'shiny.json'), shiny)
    marks.build(keys)
    import icon
    icon.main()                                        # game/icon.png
    sys.argv = sys.argv[:1]
    credits.main()                                     # WORK_DIR/tmp/CREDITS_sprites.md
    common.save_json(os.path.join(common.TMP, 'sprites_report.json'), {'missing': missing, 'species': report}, pretty=True)
    size = sum(os.path.getsize(os.path.join(SP, f)) for f in os.listdir(SP))
    print(f'sprites: {len(sprites)} keys ({len(borrowed)} on the base sprite), {len(os.listdir(SP))} sheets, '
          f'{size / 1e6:.1f} MB; shiny tables {len(shiny)}; missing {missing}; '
          f'errors {[k for k, r in report.items() if r.get("error")]}')


if __name__ == '__main__':
    main()
