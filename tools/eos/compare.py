#!/usr/bin/env python3
"""Compare this area's outputs with the reference game and the old intermediate files (verification only).

  python3 -I tools/eos/compare.py [REF_GAME] [OLD_TMP_ROOT]

REF_GAME defaults to $REF_GAME; OLD_TMP_ROOT to $OLD_EOS_ROOT
(holding the old eos/, eos_remix/ folders). Nothing is written.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import MOVEANIM, T_EOS, T_RX, common  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('REF_GAME', '')
OLD = sys.argv[2] if len(sys.argv) > 2 else os.environ.get('OLD_EOS_ROOT', '')


def same_bytes(a, b):
    if not (os.path.exists(a) and os.path.exists(b)):
        return None
    with open(a, 'rb') as f, open(b, 'rb') as g:
        return f.read() == g.read()


def same_json(a, b, ignore=None):
    if not (os.path.exists(a) and os.path.exists(b)):
        return None
    x, y = common.load_json(a), common.load_json(b)
    if ignore:
        x, y = ignore(x), ignore(y)
    return x == y


def no_index(d):
    return {**d, 'dungeons': {k: {kk: vv for kk, vv in v.items() if kk != 'index'} for k, v in d['dungeons'].items()}}


def report(label, a, b, ignore=None, note=''):
    bb = same_bytes(a, b)
    jj = bb or (a.endswith('.json') and same_json(a, b, ignore))
    st = 'MISSING' if bb is None else 'identical' if bb else 'JSON-equal' if jj else 'DIFFERENT'
    print(f'  {st:10s} {label}' + (f'   ({note})' if note and st != 'identical' else ''))
    return st


def main():
    print('intermediates (ours vs old):')
    for f in ('strings_e.json', 'eos_dungeons.json', 'eos_fixed.json', 'tilesets_eos.json'):
        report('eos/' + f, os.path.join(T_EOS, f), os.path.join(OLD, 'eos', f),
               note='vanilla conversion depends on the stage-1 items/species it is run on' if f == 'eos_dungeons.json' else '')
    for f in ('learnsets.json', 'moves_data.json', 'moves.json'):
        report('eos/moveanim/' + f, os.path.join(MOVEANIM, f), os.path.join(OLD, 'eos', 'moveanim', f))
    for f in ('strings_e.json', 'items_all.json', 'remix_data.json', 'abilities.json', 'item_p.bin', 'item_s_p.bin',
              'mappa_s.bin', 'monster.md', 'text_e.str'):
        report('eos_remix/' + f, os.path.join(T_RX, f), os.path.join(OLD, 'eos_remix', f))
    report('eos_remix/eos_dungeons.json', os.path.join(T_RX, 'eos_dungeons.json'), os.path.join(OLD, 'eos_remix', 'eos_dungeons.json'),
           ignore=no_index, note='only "index" may differ: it continues after whatever dungeons.json held when it ran')
    n = bad = 0
    old_tiles = os.path.join(OLD, 'eos', 'tiles')
    if os.path.isdir(old_tiles):
        for f in sorted(os.listdir(old_tiles)):
            n += 1
            bad += not same_bytes(os.path.join(T_EOS, 'tiles', f), os.path.join(old_tiles, f))
        print(f'  {"identical" if not bad else "DIFFERENT":10s} eos/tiles/*.png ({n - bad}/{n} byte-identical)')

    print('game files (ours vs reference):')
    for f in ('species.json', 'items.json', 'dungeons.json', 'eos_fixed.json', 'fx.json', 'move_fx.json', 'moves.json'):
        report('data/' + f, os.path.join(common.DATA, f), os.path.join(REF, 'data', f),
               note={'fx.json': 'key order of the reference came from os.listdir', 'moves.json': 'not written by this step',
                     'species.json': 'stage 1 gives the base; compare after the full build'}.get(f, ''))
    ref_fx = os.path.join(REF, 'assets', 'fx')
    if os.path.isdir(ref_fx):
        pngs = [f for f in os.listdir(ref_fx) if f.endswith('.png')]
        bad = sum(1 for f in pngs if not same_bytes(os.path.join(common.ASSETS, 'fx', f), os.path.join(ref_fx, f)))
        print(f'  {"identical" if not bad else "DIFFERENT":10s} assets/fx/*.png ({len(pngs) - bad}/{len(pngs)} byte-identical)')


if __name__ == '__main__':
    main()
