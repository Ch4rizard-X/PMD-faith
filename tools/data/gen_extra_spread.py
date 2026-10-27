#!/usr/bin/env python3
"""Spread the extra (non-Red) Pokemon through Red's AND Explorers of Sky's dungeons.

Rules (user's request): every eligible extra appears somewhere; types should fit the floor;
stronger Pokemon go to later (higher-level) floors; Red's/EoS's own Pokemon stay at >= 75% of each floor.
Works on game/data/dungeons.json in place: removes the previous extras (entries marked with a 4th
element) and places them again.
"""
import bisect
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

def save_ascii(path, obj):
    """Compact JSON with non-ASCII escaped (the format the game's species/dungeons files have always had)."""
    with open(common.p(path), 'w', encoding='utf-8') as f:
        json.dump(obj, f, separators=(',', ':'))



MAX_PER_FLOOR = 8          # extra species on one floor
SHARE = 0.25               # extras' part of a floor's spawn weight
DUNGEONS_PER_MON = 4       # best-fitting dungeons each extra lives in
SKIP = re.compile(r'^(D\d+|Boss\d+|Autopilot|DojoRegistration)$')

def apply(data, species, sprites, growth, evo, log=print):
    """Spread the extras through data (dungeons.json) in place; growth = growth.json['mon']."""
    D = data['dungeons']
    # ---- 1. drop the old extras
    for d in D.values():
        for f in d['floors']:
            f['pk'] = [e for e in f['pk'] if len(e) <= 3]

    # ---- 2. who
    extras = [k for k, v in species.items() if not v.get('red') and not v.get('megaBase') and not v.get('legend')
              and len(k) == 4 and k in sprites]
    # Pokémon that already live somewhere (Remixed's own EoS spawn lists) stay there; only the rest are spread
    native = set()
    for d in D.values():
        for f in d['floors']:
            for e in f['pk']:
                native.add(str(e[0])[:4])
    log('extras', len(extras), 'already spawning natively', sum(1 for k in extras if k in native))
    extras = [k for k in extras if k not in native]

    def power(k):
        g = growth.get(k)
        if g and isinstance(g[5], list):
            return sum(g[5])                    # Lv100 stats, laid out like Red's
        return None
    pw = {k: power(k) for k in extras}
    known = sorted(v for v in pw.values() if v)
    for k in extras:
        if pw[k] is None:
            pw[k] = known[len(known) // 2]
    ranks = sorted(pw.values())
    pct = {k: bisect.bisect_left(ranks, pw[k]) / max(1, len(ranks) - 1) for k in extras}

    # evolution stage -> allowed level band
    pre_of, evo_lv = {}, {}
    for a, lst in evo.items():
        for e in lst:
            pre_of[e[0]] = a
            evo_lv[(a, e[0])] = e[1] if isinstance(e[1], int) and e[1] > 0 else None
    def stage_range(k):
        lo = 1
        p = pre_of.get(k)
        if p:
            lo = evo_lv.get((p, k)) or 25
            if pre_of.get(p):
                lo = max(lo, 30)
        hi = 100
        nxt = evo.get(k, [])
        if nxt:
            lvs = [e[1] for e in nxt if isinstance(e[1], int) and e[1] > 0]
            hi = (min(lvs) if lvs else 35) + 12
        return lo, hi

    # ---- 3. where: every floor with wild Pokemon
    floors = []      # dict(key, fi, lv, prof, tot)
    for key, dd in D.items():
        if SKIP.match(dd['dir']):
            continue
        for fi, fl in enumerate(dd['floors']):
            if not fl['pk']:
                continue
            prof, tot = {}, 0
            for e in fl['pk']:
                w = int(e[2]); tot += w
                for t in species.get(str(e[0])[:4], {}).get('types', []):
                    prof[t] = prof.get(t, 0) + w
            lvs = sorted(int(e[1]) for e in fl['pk'])
            floors.append({'key': key, 'fi': fi, 'lv': lvs[len(lvs) // 2], 'prof': prof, 'tot': tot or 10000})
    all_lv = sorted(f['lv'] for f in floors)
    def lv_at(q):
        return all_lv[min(len(all_lv) - 1, int(q * (len(all_lv) - 1)))]

    # ---- 4. score every (extra, floor)
    opts = {}
    for k in extras:
        lo, hi = stage_range(k)
        # strength -> how far into the game: weakest at the start, strongest near the end
        target = lv_at(0.03 + 0.92 * pct[k])
        target = min(max(target, lo + 2), hi - 2) if hi - lo > 4 else (lo + hi) / 2
        ty = species[k]['types']
        per_dungeon = {}
        for f in floors:
            L = f['lv']
            if not (lo - 3 <= L <= hi):
                continue
            span = max(6.0, target * 0.35)
            if abs(L - target) > span * 1.6:
                continue
            typ = sum(f['prof'].get(t, 0) for t in ty) / f['tot']        # 0..1+ share of the floor sharing a type
            near = 1.0 - abs(L - target) / (span * 1.6)
            sc = 2.0 * min(typ, 1.0) + near + (0.0 if typ > 0 else -0.6)
            per_dungeon.setdefault(f['key'], []).append((sc, f))
        ranked = sorted(per_dungeon.items(), key=lambda kv: -max(x[0] for x in kv[1]))[:DUNGEONS_PER_MON]
        opts[k] = [(sc, f) for _key, lst in ranked for sc, f in lst]

    # widen the search for any extra with no floor (odd level bands): nearest-level floors of its types
    for k in extras:
        if opts[k]:
            continue
        lo, hi = stage_range(k)
        ty = species[k]['types']
        near = sorted(floors, key=lambda f: (abs(f['lv'] - max(lo, min(hi, f['lv']))), -sum(f['prof'].get(t, 0) for t in ty)))[:6]
        opts[k] = [(0.1, f) for f in near]

    # ---- 5. place: extras with the fewest options choose first; floors fill up to MAX_PER_FLOOR
    slot = {}        # (key, fi) -> [(score, k)]
    order = sorted(extras, key=lambda k: len(opts[k]))
    placed = {k: 0 for k in extras}
    for k in order:
        for sc, f in sorted(opts[k], key=lambda x: -x[0]):
            s = slot.setdefault((f['key'], f['fi']), [])
            if len(s) < MAX_PER_FLOOR:
                s.append((sc, k)); placed[k] += 1
    for k in order:          # nobody left out: take the best floor, replacing an extra that lives elsewhere too
        if placed[k]:
            continue
        for sc, f in sorted(opts[k], key=lambda x: -x[0]):
            s = slot.setdefault((f['key'], f['fi']), [])
            victims = sorted([x for x in s if placed[x[1]] > 1])
            if victims:
                s.remove(victims[0]); placed[victims[0][1]] -= 1
                s.append((sc, k)); placed[k] += 1
                break
        if not placed[k]:
            sc, f = max(opts[k], key=lambda x: x[0])
            slot.setdefault((f['key'], f['fi']), []).append((sc, k)); placed[k] += 1

    # ---- 6. write: the extras share a quarter of the floor at most
    fl_by = {(f['key'], f['fi']): f for f in floors}
    entries = 0
    for (key, fi), lst in slot.items():
        if not lst:
            continue
        f = fl_by[(key, fi)]
        fl = D[key]['floors'][fi]
        share = min(int(f['tot'] * SHARE / (1 - SHARE)), 1100 * len(lst))     # vs the native weight: <= 25% of the new total
        w = max(1, share // len(lst))
        for _sc, k in sorted(lst, key=lambda x: -x[0]):
            fl['pk'].append([k, int(f['lv']), w, 1]); entries += 1

    # ---- report
    none = [k for k in extras if not placed[k]]
    log('extras', len(extras), 'placed', sum(1 for k in extras if placed[k]), 'entries', entries, 'unplaced', none)
    eos_n = sum(1 for (key, fi) in slot if key.startswith('eos_') and slot[(key, fi)])
    log('floors with extras', sum(1 for v in slot.values() if v), 'of which EoS', eos_n)
    return data


def main():
    G = common.DATA
    J = lambda n: common.load_json(os.path.join(G, n))
    # species with a SpriteCollab sprite (data/sprites.json is built later, from this step's species.json)
    species = J('species.json')
    has_sprite = {k for k in species if len(k) == 4 and os.path.exists(os.path.join(common.SPRITECOLLAB, 'sprite', k, 'AnimData.xml'))}
    data = apply(J('dungeons.json'), species, has_sprite, J('growth.json')['mon'], J('evo.json'))
    save_ascii(os.path.join(G, 'dungeons.json'), data)


if __name__ == '__main__':
    main()
