#!/usr/bin/env python3
"""Compare our sprites.json / shiny.json / marks with the reference game (read only) and check the new sheets.

  python3 -I tools/sprites/compare.py [REFERENCE_GAME_DIR] [--full]

Reference: argv[1] or $REF_GAME. --full compares the pixels of every animation (slow); otherwise
Idle, Walk and one more animation per key, plus every portrait."""
import json
import os
import random
import sys
from collections import Counter, defaultdict

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith('--')]
FULL = '--full' in sys.argv
REF = args[0] if args else os.environ.get('REF_GAME', '')
OURS = common.GAME
_cache = {}


def img(root, name):
    k = (root, name)
    if k not in _cache:
        if len(_cache) > 40:
            _cache.clear()
        p = os.path.join(root, 'assets', 'sp', name)
        if not os.path.exists(p):
            _cache[k] = None
        else:
            with Image.open(p) as im:
                a = np.asarray(im.convert('RGBA')).copy()
            a[a[..., 3] == 0] = 0
            _cache[k] = a
    return _cache[k]


def frame(root, e, a, f, row):
    sheet = img(root, a.get('s', e['sheet']))
    if sheet is None:
        return None
    w, h = a['w'], a['h']
    x, y = a.get('x', 0) + f * w, a['y'] + row * h
    if 'cols' in a:
        c = a['cols']
        x, y = a.get('x', 0) + (f % c) * w, a['y'] + (f // c) * a['rows'] * h + row * h
    return sheet[y:y + h, x:x + w]


def main():
    R = common.load_json(os.path.join(REF, 'data', 'sprites.json'))
    O = common.load_json(os.path.join(OURS, 'data', 'sprites.json'))
    out = defaultdict(list)
    print(f'keys: reference {len(R)}, ours {len(O)}; missing {sorted(set(R) - set(O))}; extra {sorted(set(O) - set(R))}')
    # ---------------------------------------------------------------- loader safety (our files)
    sizes = {}
    bad_bounds = []
    for k, e in O.items():
        for nm, a in e['anims'].items():
            f = a.get('s', e['sheet'])
            p = os.path.join(OURS, 'assets', 'sp', f)
            if f not in sizes:
                sizes[f] = Image.open(p).size if os.path.exists(p) else None
            if sizes[f] is None:
                bad_bounds.append((k, nm, 'missing file ' + f))
                continue
            W, H = sizes[f]
            n = len(a['dur'])
            c = a.get('cols', n)
            lines = (n + c - 1) // c
            if a['x'] + min(c, n) * a['w'] > W or a['y'] + lines * a['rows'] * a['h'] > H:
                bad_bounds.append((k, nm, 'out of bounds'))
        for em, r in e['por'].items():
            p = os.path.join(OURS, 'assets', 'sp', r[4])
            if not os.path.exists(p):
                bad_bounds.append((k, em, 'missing portrait ' + r[4]))
    big = [f for f, s in sizes.items() if s and max(s) > 4096]
    print(f'loader checks: {len(bad_bounds)} problems {bad_bounds[:10]}; sheets over 4096 px: {big}')
    # ---------------------------------------------------------------- manifest
    rnd = random.Random(1)
    pix_ok = pix_bad = por_ok = por_bad = 0
    for k in sorted(R):
        if k not in O:
            continue
        r, o = R[k], O[k]
        if bool(r.get('base_sprite')) != bool(o.get('base_sprite')):
            out['base_sprite'].append(k)
        if r['sh'] != o['sh']:
            out['sh'].append((k, r['sh'], o['sh']))
        if r['shd'] != o['shd']:
            out['shd'].append(k)
        ra, oa = r['anims'], o['anims']
        for nm in sorted(set(ra) - set(oa)):
            out['anim missing'].append((k, nm))
        for nm in sorted(set(oa) - set(ra)):
            out['anim extra'].append((k, nm))
        for nm in sorted(set(ra) & set(oa)):
            x, y = ra[nm], oa[nm]
            if (x['w'], x['h']) != (y['w'], y['h']):
                out['frame size'].append((k, nm, (x['w'], x['h']), (y['w'], y['h'])))
            elif x['dur'] != y['dur']:
                out['durations'].append((k, nm, x['dur'], y['dur']))
            elif x['rows'] != y['rows']:
                out['rows'].append((k, nm, x['rows'], y['rows']))
        if set(r['por']) != set(o['por']):
            out['portrait emotions'].append((k, sorted(set(r['por']) - set(o['por'])), sorted(set(o['por']) - set(r['por']))))
        # pixels
        same = [nm for nm in set(ra) & set(oa) if (ra[nm]['w'], ra[nm]['h'], len(ra[nm]['dur']), ra[nm]['rows']) ==
                (oa[nm]['w'], oa[nm]['h'], len(oa[nm]['dur']), oa[nm]['rows'])]
        pick = sorted(same) if FULL else [n for n in ('Idle', 'Walk') if n in same] + rnd.sample(sorted(same), min(1, len(same)))
        for nm in pick:
            ok = True
            for f in range(len(ra[nm]['dur'])):
                for row in range(ra[nm]['rows']):
                    a, b = frame(REF, r, ra[nm], f, row), frame(OURS, o, oa[nm], f, row)
                    if a is None or b is None or not np.array_equal(a, b):
                        ok = False
            if ok:
                pix_ok += 1
            else:
                pix_bad += 1
                out['pixels differ'].append((k, nm))
        for em in set(r['por']) & set(o['por']):
            a = img(REF, r['por'][em][4])
            b = img(OURS, o['por'][em][4])
            x0, y0, w, h = r['por'][em][:4]
            x1, y1 = o['por'][em][:2]
            if a is not None and b is not None and np.array_equal(a[y0:y0 + h, x0:x0 + w], b[y1:y1 + h, x1:x1 + w]):
                por_ok += 1
            else:
                por_bad += 1
                out['portrait pixels differ'].append((k, em))
    print(f'pixel checks: animations {pix_ok} equal, {pix_bad} differ; portraits {por_ok} equal, {por_bad} differ')
    for cat, items in out.items():
        print(f'-- {cat}: {len(items)}')
        for it in items[:60]:
            print('   ', it)
    # ---------------------------------------------------------------- shiny
    RS = common.load_json(os.path.join(REF, 'data', 'shiny.json'))
    OS_ = common.load_json(os.path.join(OURS, 'data', 'shiny.json'))
    diff = Counter()
    ex = defaultdict(list)
    for k in sorted(set(RS) | set(OS_)):
        for t in ('s', 'p'):
            a, b = RS.get(k, {}).get(t), OS_.get(k, {}).get(t)
            if a == b:
                diff['same'] += 1 if a else 0
            elif a is None:
                diff['extra ' + t] += 1
                ex['extra ' + t].append(k)
            elif b is None:
                diff['missing ' + t] += 1
                ex['missing ' + t].append(k)
            else:
                diff['differ ' + t] += 1
                ex['differ ' + t].append(k)
    print('shiny:', dict(diff), {k: v[:30] for k, v in ex.items()})
    # ---------------------------------------------------------------- marks
    RM = common.load_json(os.path.join(REF, 'data', 'marks.json'))
    OM = common.load_json(os.path.join(OURS, 'data', 'marks.json'))
    md = {k: (RM['size'].get(k), OM['size'].get(k)) for k in set(RM['size']) | set(OM['size']) if RM['size'].get(k) != OM['size'].get(k)}
    pm = []
    for f in sorted(os.listdir(os.path.join(REF, 'assets', 'ui'))):
        if f.startswith('mark_') and f.endswith('.png'):
            a = np.asarray(Image.open(os.path.join(REF, 'assets', 'ui', f)).convert('RGBA'))
            p = os.path.join(OURS, 'assets', 'ui', f)
            if not os.path.exists(p) or not np.array_equal(a, np.asarray(Image.open(p).convert('RGBA'))):
                pm.append(f)
    print(f'marks: offsets equal {RM["off"] == OM["off"]}; size differences {md}; images differing {pm}')
    tot = lambda root: sum(os.path.getsize(os.path.join(root, 'assets', 'sp', f)) for f in os.listdir(os.path.join(root, 'assets', 'sp'))
                           if not f.endswith('.import'))
    print(f'assets/sp size: reference {tot(REF) / 1e6:.0f} MB, ours {tot(OURS) / 1e6:.0f} MB')


if __name__ == '__main__':
    main()
