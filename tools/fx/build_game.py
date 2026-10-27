#!/usr/bin/env python3
"""Game files from the move-animation intermediates (tmp/eos/moveanim):
  game/assets/fx/fx_NNNN.png   the effect sheets (copied as they are)
  game/data/fx.json            fx id -> {k: 'p' sprite | 's' screen, dir: directional, a: {direction: [[x, y, w, h, ox, oy, frames(, alpha)]]}}
  game/data/move_fx.json       normalised move name -> {n: name, ua: user body animation, ppf: projectile px/frame (3 if none),
                               s: [{fx, r: role, w: where, at: attach, d: 1 user facing / 0 down / -1 screen, b: blocking, l: loop}]}
"""
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tables import MOVEANIM, SHEETS, common  # noqa: E402

norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
DIRECTION = {'user_facing': 1, 'down(0)': 0, None: -1}


def frame(f, screen):
    a = [f['x'], f['y'], f['w'], f['h'], f['ox'], f['oy'], f['duration']]
    if screen:
        a.append(round(f['alpha'], 3))
    return a


def main():
    out_dir = os.path.join(common.ASSETS, 'fx')
    os.makedirs(out_dir, exist_ok=True)
    fx = {}
    for name in sorted(os.listdir(SHEETS)):
        if not name.endswith('.json'):
            continue
        meta = common.load_json(os.path.join(SHEETS, name))
        scr = meta['kind'] == 'screen'
        fx[str(meta['fx'])] = {'k': 's' if scr else 'p', 'dir': meta['directional'],
                               'a': {d: [frame(f, scr) for f in lst] for d, lst in meta['animations'].items()}}
        shutil.copyfile(os.path.join(SHEETS, meta['image']), os.path.join(out_dir, meta['image']))
    moves = {}
    for nm, m in common.load_json(os.path.join(MOVEANIM, 'moves.json')).items():
        moves[norm(nm)] = {'n': nm, 'ua': m['user_anim_name'], 'ppf': m['projectile_px_per_frame'] or 3,
                           's': [{'fx': s['fx'], 'r': s['role'], 'w': s['where'], 'at': s['attach'], 'd': DIRECTION[s['direction']],
                                  'b': s['blocking'], 'l': s['loop']} for s in m['steps']]}
    common.save_json(os.path.join(common.DATA, 'fx.json'), fx)
    common.save_json(os.path.join(common.DATA, 'move_fx.json'), moves)
    print('fx:', len(fx), 'effect sheets,', len(moves), 'moves')


if __name__ == '__main__':
    main()
