#!/usr/bin/env python3
"""Compare this area's outputs with the reference game (argv[1]), read only.
Images: same size? % of identical pixels (all fully transparent pixels count as equal, whatever RGB they carry).
JSON: same keys, equal values (tilesets: rules equal)."""
import json, os, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import common

REF = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('REF_GAME', '')


def norm(path):
    a = np.array(Image.open(path).convert('RGBA'))
    a[a[..., 3] == 0] = 0
    return a


def cmp_img(mine, ref):
    if not os.path.exists(mine):
        return 'MISSING', 0.0
    a, b = norm(mine), norm(ref)
    if a.shape != b.shape:
        return 'size %s vs %s' % (a.shape[1::-1], b.shape[1::-1]), 0.0
    return 'same size', float((a == b).all(-1).mean() * 100)


def cmp_dir(sub):
    md, rd = os.path.join(common.ASSETS, sub), os.path.join(REF, 'assets', sub)
    rf = sorted(f for f in os.listdir(rd) if not f.endswith('.import'))
    mf = sorted(f for f in os.listdir(md) if not f.endswith('.import'))
    extra = sorted(set(mf) - set(rf))
    res = {}
    for f in rf:
        res[f] = cmp_img(os.path.join(md, f), os.path.join(rd, f))
    return res, extra


def deep_eq(a, b):
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def main():
    load = lambda base, n: common.load_json(os.path.join(base, n))
    ok = True
    # ---- tilesets
    mt, rt = load(common.DATA, 'tilesets.json'), load(os.path.join(REF, 'data'), 'tilesets.json')
    print('== data/tilesets.json: %d keys (ref %d), missing %s, extra %s' % (
        len(mt), len(rt), sorted(set(rt) - set(mt)), sorted(set(mt) - set(rt))))
    print('%-6s %-10s %-9s %8s %8s %s' % ('key', 'size', 'rules', 'img %', 'hd %', 'other fields'))
    for k in rt:
        r, m = rt[k], mt.get(k)
        if m is None:
            print(k, 'MISSING'); ok = False; continue
        s, pct = cmp_img(os.path.join(common.ASSETS, 'tiles', m['img']), os.path.join(REF, 'assets', 'tiles', r['img']))
        hd = ''
        if 'hd' in r:
            hs, hp = cmp_img(os.path.join(common.ASSETS, 'tiles', m.get('hd', '-')), os.path.join(REF, 'assets', 'tiles', r['hd']))
            hd = '%.2f' % hp if hs == 'same size' else hs
        other = 'ok' if all(m.get(f) == r.get(f) for f in ('img', 'hd', 'cols')) else 'DIFF'
        print('%-6s %-10s %-9s %8.2f %8s %s' % (k, s, 'equal' if m['rules'] == r['rules'] else 'DIFFERENT', pct, hd, other))
        ok &= m['rules'] == r['rules'] and s == 'same size'
    # ---- assets/dungeon
    res, extra = cmp_dir('dungeon')
    print('== assets/dungeon: %d files, extra %s' % (len(res), extra))
    for f, (s, pct) in res.items():
        if s != 'same size' or pct < 100:
            print('   %-20s %-12s %.2f%%' % (f, s, pct))
    print('   identical: %d / %d' % (sum(1 for s, p in res.values() if s == 'same size' and p == 100), len(res)))
    # ---- json
    for n in ('dungeon_gfx.json', 'dungeon_talk.json'):
        m, r = load(common.DATA, n), load(os.path.join(REF, 'data'), n)
        diffs = [k for k in set(m) | set(r) if not deep_eq(m.get(k), r.get(k))]
        print('== data/%s: %s' % (n, 'equal' if not diffs else 'differs in ' + str(sorted(diffs))))
        for k in sorted(diffs):
            if isinstance(r.get(k), dict) and isinstance(m.get(k), dict):
                sub = [kk for kk in set(m[k]) | set(r[k]) if not deep_eq(m[k].get(kk), r[k].get(kk))]
                print('   %s: %d sub-keys differ, e.g. %s' % (k, len(sub), sorted(sub)[:8]))
    return ok


if __name__ == '__main__':
    main()
