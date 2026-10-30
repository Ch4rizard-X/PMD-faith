#!/usr/bin/env python3
"""Spread the extra (non-Red) Pokemon through Red's AND Explorers of Sky's dungeons.

Rules: every Pokemon (but Kecleon) appears in at least one of Red's dungeons; types fit the floor; nobody is much
stronger than the floor's own Pokemon at its level; legendaries / Ultra Beasts / Paradox Pokemon are rare spawns deep
in late-game dungeons; Red's/EoS's own Pokemon stay at >= 75% of each floor. Also used by gen_dungeons.py (stage 1,
Red's dungeons alone) so a Red-only setup gets the same.
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
STRONG_CAP = 1.15          # an extra's stats at the floor's level: at most this times the floor's strongest own Pokémon
SPECIAL_CAP = 1.35         # legendaries / Ultra Beasts / Paradox Pokémon: rare and a little stronger than the floor
SPECIAL_SHARE = 0.02       # each special's part of its floor (rare)
SPECIAL_DUNGEONS = 2       # dungeons each special lives in (the deepest floors of each)
SPECIALS_PER_FLOOR = 3     # so the legendaries don't crowd the same few floors (each is ~2% of it)
SPECIALS_PER_DUNGEON = 4     # at least; long dungeons take one per two deep floors
SPECIAL_FLOORS = 3           # floors each special spawns on in each of its dungeons
SKIP = re.compile(r'^(D\d+|Boss\d+|Autopilot|DojoRegistration)$')
KECLEON = '0352'           # the shopkeeper stays a shopkeeper (recruited only by fighting him as a thief)
# Ultra Beasts and Paradox Pokémon: species data doesn't flag them as legendary, but they are placed like one
# when a Pokémon's own types aren't on a floor: types whose places suit it (half a match). Red has no Fairy type at all.
AFFINITY = {'Fairy': ['Normal', 'Psychic', 'Grass', 'Flying'], 'Steel': ['Rock', 'Ground', 'Electric'],
            'Dark': ['Ghost', 'Poison', 'Psychic'], 'Dragon': ['Flying', 'Rock', 'Ground'], 'Ice': ['Water'],
            'Ghost': ['Dark', 'Poison', 'Psychic'], 'Psychic': ['Ghost', 'Normal', 'Fairy'], 'Fighting': ['Rock', 'Normal', 'Ground'],
            'Bug': ['Grass', 'Poison'], 'Poison': ['Bug', 'Grass', 'Ghost'], 'Rock': ['Ground', 'Steel'], 'Ground': ['Rock', 'Steel'],
            'Grass': ['Bug', 'Water'], 'Water': ['Ice'], 'Fire': ['Ground', 'Rock'], 'Electric': ['Steel', 'Flying'],
            'Normal': ['Fairy', 'Flying'], 'Flying': ['Normal', 'Grass']}
SPECIAL_NUMS = set(range(793, 800)) | set(range(803, 807)) | set(range(984, 996)) | {1005, 1006, 1009, 1010} | set(range(1020, 1024))


def stats_total(growth, curve, species, sp, L):
    """Sum of HP / Attack / Sp. Atk / Defense / Sp. Def at level L, as the game works it out (scripts/core/db.gd stats_at)."""
    L = max(1, min(100, int(L)))
    d = growth.get(sp) or growth.get(sp[:4])
    if d is None:
        b = species.get(sp, {}).get('b', [50] * 6)
        return int(2 * b[0] * L / 100) + L + 10 + sum(int(2 * b[i + 1] * L / 100) + 5 for i in range(4))
    if isinstance(d[5], str):          # Red's own Pokémon: per-level gains
        tot = 0
        for j in range(5):
            v = int(d[j])
            for lv in range(2, L + 1):
                v += ord(d[5][j * 99 + lv - 2]) - 48
            tot += v
        return tot
    return sum(round(d[j] + (d[5][j] - d[j]) * curve[j][L - 1]) for j in range(5))


def apply(data, species, sprites, growth, evo, log=print, curve=None):
    """Spread the extras through data (dungeons.json) in place; growth = growth.json['mon'], curve = growth.json['curve'].

    Every Pokémon with a sprite gets at least one spot in Red's own dungeons (so it can be met whatever the launcher's
    Game page says), and more in Explorers of Sky's when they're there. Rules:
      - strength: at the floor's level an extra is at most STRONG_CAP times the floor's strongest own Pokémon
      - type: it shares a type with the floor's own Pokémon (unless nothing fits)
      - level: the floor's own level, inside the extra's evolution band
      - specials (legendaries, mythicals, Ultra Beasts, Paradox Pokémon) are rare spawns on the deepest floors of
        late-game dungeons of their type, up to SPECIAL_CAP times the floor's strongest
      - the floor's own Pokémon keep at least 75% of the spawns; Kecleon is never placed
    """
    D = data['dungeons']
    curve = curve or []
    st = lambda sp, L: stats_total(growth, curve, species, sp, L)
    # ---- 1. drop the old extras
    for d in D.values():
        for f in d['floors']:
            f['pk'] = [e for e in f['pk'] if len(e) <= 3]

    # ---- 2. who
    def is_special(k):
        return bool(species[k].get('legend')) or int(k) in SPECIAL_NUMS
    pool = [k for k, v in species.items() if len(k) == 4 and k.isdigit() and k in sprites and k != KECLEON
            and not v.get('megaBase')]
    # where each already lives (Red's own lists, Remixed's Explorers of Sky lists)
    native_red, native_any = set(), set()
    for key, d in D.items():
        for f in d['floors']:
            for e in f['pk']:
                if int(e[2]) > 0:
                    native_any.add(str(e[0])[:4])
                    if not d.get('eos'):
                        native_red.add(str(e[0])[:4])
    extras = [k for k in pool if k not in native_red]        # everyone without a spot in Red's dungeons
    log('Pokémon', len(pool), 'already in Red dungeons', len(pool) - len(extras), 'to place', len(extras),
        'of which specials', sum(1 for k in extras if is_special(k)))

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

    # ---- 3. where: every floor with wild Pokémon of its own
    floors = []
    for key, dd in D.items():
        if SKIP.match(dd['dir']):
            continue
        n = len(dd['floors'])
        for fi, fl in enumerate(dd['floors']):
            own = [e for e in fl['pk'] if int(e[2]) > 0 and not str(e[0]).startswith(KECLEON)]
            if not own:
                continue
            prof, tot = {}, 0
            for e in own:
                w = int(e[2]); tot += w
                for t in species.get(str(e[0])[:4], {}).get('types', []):
                    prof[t] = prof.get(t, 0) + w
            lvs = sorted(int(e[1]) for e in own)
            lv = lvs[len(lvs) // 2]
            floors.append({'key': key, 'fi': fi, 'lv': lv, 'prof': prof, 'tot': tot or 10000, 'eos': bool(dd.get('eos')),
                           'strong': max(st(str(e[0]), int(e[1])) for e in own), 'depth': (fi + 1) / n})
    all_lv = sorted(f['lv'] for f in floors if not f['eos'])
    def lv_at(q):
        return all_lv[min(len(all_lv) - 1, int(q * (len(all_lv) - 1)))]
    late_lv = lv_at(0.7)              # late game: the top 30% of Red's floor levels

    def power(k):
        g = growth.get(k)
        return sum(g[5]) if g and isinstance(g[5], list) else st(k, 100)
    pw = {k: power(k) for k in extras}
    ranks = sorted(pw.values())
    pct = {k: bisect.bisect_left(ranks, pw[k]) / max(1, len(ranks) - 1) for k in extras}

    def fit(k, f):
        """How well k's types suit floor f: the share of the floor's own Pokémon of its types, plus half the share of
        related types (AFFINITY) when none of its own are there."""
        ty = species[k]['types']
        direct = sum(f['prof'].get(t, 0) for t in ty) / f['tot']
        if direct > 0:
            return direct
        return 0.5 * sum(f['prof'].get(a, 0) for t in ty for a in AFFINITY.get(t, [])) / f['tot']
    def direct(k, f):                                # one of k's own types lives on the floor
        return any(f['prof'].get(t, 0) > 0 for t in species[k]['types'])
    def at(k, L):                                    # the level k spawns at on a floor of level L
        lo, hi = stage_range(k)
        return int(max(lo, min(hi, L)))

    # ---- 4. ordinary extras: score every fitting floor
    opts = {}
    normal = [k for k in extras if not is_special(k)]
    for k in normal:
        lo, hi = stage_range(k)
        target = lv_at(0.03 + 0.92 * pct[k])
        target = min(max(target, lo + 2), hi - 2) if hi - lo > 4 else (lo + hi) / 2
        ty = species[k]['types']
        per_dungeon = {}
        for f in floors:
            L = f['lv']
            if not (lo - 3 <= L <= hi):
                continue
            if st(k, at(k, L)) > STRONG_CAP * f['strong']:
                continue                                         # too strong for this floor
            typ = fit(k, f)
            if typ <= 0:
                continue
            span = max(6.0, target * 0.35)
            near = max(0.0, 1.0 - abs(L - target) / (span * 1.6))
            sc = 2.0 * min(typ, 1.0) + near + (1.5 if direct(k, f) else 0.0)     # its own types always beat related ones
            per_dungeon.setdefault(f['key'], []).append((sc, f, at(k, L)))
        if not any(direct(k, f) for lst in per_dungeon.values() for _sc, f, _l in lst):
            # no floor of its own type in its level band: own-type floors below it, at the floor's own level (as Red
            # does with evolved Pokémon), still no stronger than the floor allows
            for f in floors:
                L = f['lv']
                if L >= lo - 3 or not direct(k, f) or st(k, L) > STRONG_CAP * f['strong']:
                    continue
                sc = 2.0 * min(fit(k, f), 1.0) + 1.5 - (lo - L) / 40.0
                per_dungeon.setdefault(f['key'], []).append((sc, f, L))
        if any(direct(k, f) for lst in per_dungeon.values() for _sc, f, _l in lst):     # own types only, when there are any
            per_dungeon = {key: [x for x in lst if direct(k, x[1])] for key, lst in per_dungeon.items()}
            per_dungeon = {key: lst for key, lst in per_dungeon.items() if lst}
        red = sorted([kv for kv in per_dungeon.items() if not D[kv[0]].get('eos')], key=lambda kv: -max(x[0] for x in kv[1]))
        eos = sorted([kv for kv in per_dungeon.items() if D[kv[0]].get('eos')], key=lambda kv: -max(x[0] for x in kv[1]))
        nr = 2 if eos else DUNGEONS_PER_MON                   # at least two Red dungeons, the rest Explorers of Sky
        ranked = red[:nr] + eos[:DUNGEONS_PER_MON - min(nr, len(red))] if k not in native_any else red[:2]
        opts[k] = [(sc, f, L) for _key, lst in ranked for sc, f, L in lst]
    # no floor passed every rule: drop the type rule, then take the floors where it's weakest compared to the natives
    for k in normal:
        if any(not f['eos'] for _sc, f, _l in opts[k]):
            continue
        lo, hi = stage_range(k)
        ty = species[k]['types']
        red_f = [f for f in floors if not f['eos']]
        ok = [f for f in red_f if lo - 3 <= f['lv'] <= hi and st(k, at(k, f['lv'])) <= STRONG_CAP * f['strong']]
        if not ok:
            ok = sorted(red_f, key=lambda f: st(k, at(k, f['lv'])) / f['strong'])[:12]
        ok = sorted(ok, key=lambda f: (not direct(k, f), -fit(k, f), abs(f['lv'] - at(k, f['lv']))))[:6]
        opts[k] = opts[k] + [(0.1, f, at(k, f['lv'])) for f in ok]

    # ---- 5. place ordinary extras: fewest options first; floors fill up to MAX_PER_FLOOR
    slot = {}
    order = sorted(normal, key=lambda k: len(opts[k]))
    placed = {k: 0 for k in extras}
    for k in order:
        for sc, f, L in sorted(opts[k], key=lambda x: -x[0]):
            s = slot.setdefault((f['key'], f['fi']), [])
            if len(s) < MAX_PER_FLOOR:
                s.append((sc, k, 'n', L)); placed[k] += 1
    for k in order:          # nobody left out: take the best floor, replacing an extra that lives elsewhere too
        if placed[k]:
            continue
        for sc, f, L in sorted(opts[k], key=lambda x: -x[0]):
            s = slot.setdefault((f['key'], f['fi']), [])
            victims = sorted([x for x in s if placed[x[1]] > 1 and x[2] == 'n'], key=lambda x: x[0])
            if victims:
                s.remove(victims[0]); placed[victims[0][1]] -= 1
                s.append((sc, k, 'n', L)); placed[k] += 1
                break
        if not placed[k] and opts[k]:
            sc, f, L = max(opts[k], key=lambda x: x[0])
            slot.setdefault((f['key'], f['fi']), []).append((sc, k, 'n', L)); placed[k] += 1

    # ---- 6. specials: the deepest floors (last 40%) of late-game dungeons of their type, rare
    by_dungeon = {}
    for f in floors:
        by_dungeon.setdefault(f['key'], []).append(f)
    fit_ = fit
    sp_floor, sp_dungeon = {}, {}
    for k in sorted([k for k in extras if is_special(k)], key=lambda k: -pw[k]):
        ty = species[k]['types']
        lo, _hi = stage_range(k)
        cands = []
        for key, fl in by_dungeon.items():
            deep = [f for f in fl if f['depth'] > 0.6 and f['lv'] >= lo]
            fitting = [f for f in deep if st(k, f['lv']) <= SPECIAL_CAP * f['strong']]
            if not fitting:
                continue
            late = [f for f in fitting if f['lv'] >= late_lv]
            use = late or fitting
            own = [f for f in use if direct(k, f)]
            use = own or use
            typ = max(fit_(k, f) for f in use)
            ratio = min(st(k, f['lv']) / f['strong'] for f in use)
            # late game first, then its own type, then related types, then the closest strength
            cands.append((bool(late), bool(own), typ, -ratio, key, use))
        red = sorted([c for c in cands if not D[c[4]].get('eos')], key=lambda c: c[:4], reverse=True)
        eos = sorted([c for c in cands if D[c[4]].get('eos')], key=lambda c: c[:4], reverse=True)
        if not red:                                              # nothing deep enough fits: the strongest Red floors
            red_f = sorted([f for f in floors if not f['eos']], key=lambda f: -f['strong'])[:3]
            red = [(False, False, 0, 0, red_f[0]['key'], red_f)] if red_f else []
        got = 0
        for gi, group in enumerate([red, eos] if eos else [red, red]):    # one Red dungeon (always) and one more
            if got > gi:
                continue
            for c in group:
                key = c[4]
                if gi == 1 and not eos and not c[0]:
                    continue                                     # a second Red dungeon only if it's a late-game one
                if any(x for x in sp_dungeon.get(key, set()) if x == k):
                    continue
                if len(sp_dungeon.get(key, set())) >= max(SPECIALS_PER_DUNGEON, len(c[5])):
                    continue
                free = [f for f in sorted(c[5], key=lambda f: -f['depth']) if sp_floor.get((f['key'], f['fi']), 0) < SPECIALS_PER_FLOOR][:SPECIAL_FLOORS]
                if not free:
                    continue
                for f in free:
                    slot.setdefault((f['key'], f['fi']), []).append((0.0, k, 's', int(f['lv']))); placed[k] += 1
                    sp_floor[(f['key'], f['fi'])] = sp_floor.get((f['key'], f['fi']), 0) + 1
                sp_dungeon.setdefault(key, set()).add(k)
                got += 1
                break
        if not placed[k] and red:                                # every floor full: the least crowded floor of the best
            c = red[0]
            f = min(c[5], key=lambda f: (sp_floor.get((f['key'], f['fi']), 0), -f['depth']))
            slot.setdefault((f['key'], f['fi']), []).append((0.0, k, 's', int(f['lv']))); placed[k] += 1
            sp_floor[(f['key'], f['fi'])] = sp_floor.get((f['key'], f['fi']), 0) + 1

    # ---- 7. write: ordinary extras share a quarter of the floor at most; specials are rare
    fl_by = {(f['key'], f['fi']): f for f in floors}
    entries = 0
    for (key, fi), lst in slot.items():
        if not lst:
            continue
        f = fl_by[(key, fi)]
        fl = D[key]['floors'][fi]
        nrm = [x for x in lst if x[2] == 'n']
        if nrm:
            share = min(int(f['tot'] * SHARE / (1 - SHARE)), 1100 * len(nrm))
            w = max(1, share // len(nrm))
            for _sc, k, _t, L in sorted(nrm, key=lambda x: -x[0]):
                fl['pk'].append([k, int(L), w, 1]); entries += 1
        for _sc, k, _t, L in [x for x in lst if x[2] == 's']:
            fl['pk'].append([k, int(L), max(1, int(f['tot'] * SPECIAL_SHARE)), 1]); entries += 1

    # ---- report
    none = [k for k in extras if not placed[k]]
    log('placed', sum(1 for k in extras if placed[k]), 'of', len(extras), 'entries', entries,
        'unplaced', [species[k]['name'] for k in none])
    return data


def main():
    G = common.DATA
    J = lambda n: common.load_json(os.path.join(G, n))
    # species with a SpriteCollab sprite (data/sprites.json is built later, from this step's species.json)
    species = J('species.json')
    has_sprite = {k for k in species if len(k) == 4 and os.path.exists(os.path.join(common.SPRITECOLLAB, 'sprite', k, 'AnimData.xml'))}
    gr = J('growth.json')
    data = apply(J('dungeons.json'), species, has_sprite, gr['mon'], J('evo.json'), curve=gr['curve'])
    save_ascii(os.path.join(G, 'dungeons.json'), data)


if __name__ == '__main__':
    main()
