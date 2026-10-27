"""Rebuilds the tables the old HTML prototype of this remake carried (SPECIES, MOVES, PMD growth numbers, EVO, ITEMS)
from public sources only:
  - main-series data (base stats, types, abilities, learnsets, moves) from PokeAPI,
  - Red's own numbers (level-up stat gains, exp tables, base stats, exp yield, recruit rates, evolutions) from the
    pret/pmd-red decompilation and the user's Red ROM,
  - the prototype's own design choices (which abilities/moves it supports, ability substitutes, item behaviour,
    hand-written move effects) from proto_tables.py.
The old prototype's generators were rt/work/gen/gen_pmd.py, gen_evo.py, gen_mega.py; this file follows them step by step.
gen_data.py turns the result into game/data/{species,growth,evo,moves,items}.json."""
import bisect
import json
import os
import re
import sys
from collections import defaultdict

import numpy as np

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
import proto_tables as T  # noqa: E402
import redsrc  # noqa: E402
from pokeapi import PA  # noqa: E402

key_of = lambda n: "%04d" % int(n)


def num(x):
    """JSON numbers as the prototype's JavaScript wrote them (1.0 -> 1)."""
    return int(x) if isinstance(x, float) and x.is_integer() else x


# ---------------------------------------------------------------- species list
def species_keys(pa):
    """National dex numbers the prototype had: every species with a SpriteCollab sprite (minus newer additions)."""
    out = []
    for i in range(1, 1026):
        k = key_of(i)
        if k in T.LATER_SPRITES or str(i) not in pa.species:
            continue
        if os.path.exists(os.path.join(common.SPRITECOLLAB, "sprite", k, "AnimData.xml")) or k in T.EXTRA_SPECIES:
            out.append(k)
    return out


def _abilities(pa, sid, k):
    if k in T.ABILITY_OVERRIDE:
        return list(T.ABILITY_OVERRIDE[k])
    sup = set(T.ABILITIES)
    lst = sorted(pa.abilities[sid])
    normal = [a for _, a, h in lst if not h]
    hidden = [a for _, a, h in lst if h]
    keep = [a for a in normal if a in sup]
    if keep:
        return keep
    keep = [a for a in hidden if a in sup]
    if keep:
        return keep[:1]
    out = []
    for a in normal:
        s = T.ABILITY_SUB.get(a)
        if s and s not in out:
            out.append(s)
    return out


def _learnset(pa, sid, supported):
    """Level-up moves from the newest main-series game the species is in (prototype's version priority),
    level 0 (evolution moves) as level 1, each move once, only moves the prototype supports."""
    lu = pa.levelup()[sid]
    vg = next(str(v) for v in T.VG_PRIORITY if str(v) in lu)
    out, seen = [], set()
    for lv, _, n in sorted(lu[vg], key=lambda x: (x[0], x[1])):   # ties keep PokeAPI's row order
        if n not in supported or n in seen:
            continue
        seen.add(n)
        out.append([max(1, lv), n])
    return out


def build_dex(pa, supported_moves):
    keys = species_keys(pa)
    kset = set(keys)
    into = defaultdict(list)
    for s in pa.species.values():
        if s["evolves_from_species_id"]:
            into[key_of(s["evolves_from_species_id"])].append(key_of(s["id"]))
    dex = {}
    for k in keys:
        sid = str(int(k))
        s = pa.species[sid]
        d = {"name": pa.species_name[sid], "types": pa.type_list(sid), "b": pa.base_stats(sid),
             "xp": int(pa.pokemon[sid]["base_experience"] or 0), "ab": _abilities(pa, sid, k),
             "learn": T.LEARN_OVERRIDE.get(k) or _learnset(pa, sid, supported_moves)}
        if s["evolves_from_species_id"]:
            d["pre"] = key_of(s["evolves_from_species_id"])
        if not any(t in kset for t in into.get(k, [])):
            d["fin"] = 1
        if s["is_legendary"] == "1" or s["is_mythical"] == "1":
            d["lg"] = 1
        if s["is_baby"] == "1":
            d["baby"] = 1
        dex[k] = d
    return dex


# ---------------------------------------------------------------- moves (main-series data -> prototype descriptors)
STAT = {2: "atk", 3: "def", 4: "spa", 5: "spd", 6: "spe", 7: "acc", 8: "eva"}
AILMENT = {"burn": "burn", "freeze": "petrify", "paralysis": "para", "poison": "poison", "sleep": "sleep",
           "confusion": "confuse", "infatuation": "infatuate", "leech-seed": "leech"}
SELF_TARGETS = {"user", "user-and-allies", "users-field", "ally", "user-or-ally", "entire-field"}
RANGE = {"user": "self", "user-and-allies": "self", "users-field": "self", "entire-field": "self", "ally": "self",
         "all-opponents": "room", "all-other-pokemon": "room", "all-pokemon": "room", "opponents-field": "room"}
EFFECT_KEY = {88: ("fixed", "lvl"), 41: ("fixed", "half"), 190: ("fixed", "half"), 116: ("weather", "sand"),
              137: ("weather", "rain"), 138: ("weather", "sun"), 165: ("weather", "hail"), 39: ("ohko", 1), 103: ("cure", 1),
              125: ("cure", 1), 29: ("blow", 1), 8: ("selfko", 1), 169: ("selfko", 1), 321: ("selfko", 1), 154: ("warp", 1),
              26: ("haze", 1), 84: ("metro", 1), 58: ("transform", 1), 96: ("sketch", 1), 143: ("hpcost", 0.5)}
EFFECT_KEYS = {"eff", "heal", "drain", "recoil", "fixed", "weather", "ohko", "cure", "blow", "selfko", "warp", "haze",
               "metro", "transform", "sketch", "hpcost"}


def _chance(v):
    v = int(v or 0)
    return v / 100 if 0 < v < 100 else None


def _effects(pa, mid):
    m = pa.moves[mid]
    mm = pa.move_meta.get(mid)
    if not mm:
        return None
    out = []
    a = pa.ailment[mm["meta_ailment_id"]]
    if a in AILMENT:
        e = {"status": AILMENT[a]}
        c = _chance(mm["ailment_chance"])
        if c:
            e["ch"] = c
        out.append(e)
    cat = pa.meta_cat[mm["meta_category_id"]]
    for s, v in pa.move_stat.get(mid, []):
        if s not in STAT:
            continue
        me = cat == "damage-raise" or (cat != "damage-lower" and pa.target[m["target_id"]] in SELF_TARGETS)
        if STAT[s] == "spe":
            if me and v > 0:
                e = {"fast": 8}
            elif not me and v < 0:
                e = {"status": "slow"}
            else:
                continue
        else:
            e = {"self" if me else "tgt": STAT[s], "st": v}
        c = _chance(mm["stat_chance"])
        if c:
            e["ch"] = c
        out.append(e)
    if not out:
        return None
    return out[0] if len(out) == 1 else out


def main_series_move(pa, name):
    """The prototype's main-series view of a move (dexmoves): t, c, p, a, pp, r and effect descriptors."""
    mid = pa.move_by_name[name]
    m = pa.moves[mid]
    mm = pa.move_meta.get(mid) or {}
    o = {"t": pa.type_name[m["type_id"]], "c": {"1": "X", "2": "P", "3": "S"}[m["damage_class_id"]]}
    if m["power"] and int(m["power"]) > 0:
        o["p"] = int(m["power"])
    elif o["c"] != "X":
        o["p"] = 60                                  # variable-power moves
    o["a"] = int(m["accuracy"]) if m["accuracy"] else (100 if o["c"] == "X" else 999)
    o["pp"] = int(m["pp"])
    r = RANGE.get(pa.target[m["target_id"]])
    if r:
        o["r"] = r
    e = _effects(pa, mid)
    if e:
        o["eff"] = e
    if mm:
        if int(mm["healing"]) > 0:
            o["heal"] = num(int(mm["healing"]) / 100)
        if int(mm["drain"]) > 0:
            o["drain"] = num(int(mm["drain"]) / 100)
        if int(mm["drain"]) < 0:
            o["recoil"] = num(-int(mm["drain"]) / 100)
        if int(mm["crit_rate"]) > 0:
            o["crit"] = 1
        if mm["max_hits"] and int(mm["max_hits"]) > 1:
            o["hits"] = [int(mm["min_hits"]), int(mm["max_hits"])]
    fx = EFFECT_KEY.get(int(m["effect_id"] or 0))
    if fx:
        o[fx[0]] = fx[1]
    for f, v in T.MOVE_OVERRIDE.get(name, {}).items():
        if v is None:
            o.pop(f, None)
        else:
            o[f] = v
    return o


def build_dexmoves(pa, keys):
    """All level-up moves of the species the prototype could express: damaging moves, and status moves with an effect."""
    used = set()
    lu = pa.levelup()
    for k in keys:
        sid = str(int(k))
        vg = next(str(v) for v in T.VG_PRIORITY if str(v) in lu[sid])
        used.update(n for _, _, n in lu[sid][vg])
    out = {}
    for mid in sorted(pa.moves, key=int):
        n = pa.move_name.get(mid)
        if n not in used:
            continue
        o = main_series_move(pa, n)
        if o["c"] != "X" or EFFECT_KEYS & set(o):
            out[n] = o
    return out


# ---------------------------------------------------------------- Red's numbers and the derived ones (gen_pmd.py)
def red_records(dex):
    """dex key -> Red's base stats (hp, atk, spa, def, spd), level-up gains, exp table, exp yield, recruit rate."""
    mons = redsrc.load("data/monster/monster_data.json")
    arc = redsrc.Archive(redsrc.SYSTEM_ARCHIVE)
    red = {}
    for i, m in enumerate(mons):
        d = m["dexInternal"][0]
        if not (1 <= d <= 386) or ("lvmp%03d" % i) not in arc.files:
            continue
        k = key_of(d)
        if k in red or k not in dex:
            continue
        L = redsrc.level_table(i)
        b1 = [m["baseHP"], m["baseAtkSpAtk"][0], m["baseAtkSpAtk"][1], m["baseDefSpDef"][0], m["baseDefSpDef"][1]]
        gains = [[row[j + 1] for row in L[1:]] for j in range(5)]          # levels 2..100
        red[k] = dict(b1=b1, gains=gains, xp=[row[0] for row in L], ey=m["expYield"], rr=m["recruitRate"],
                      s100=[b1[j] + sum(gains[j]) for j in range(5)])
    return red


def _stage(dex, k):
    d = dex[k]
    if d.get("lg"):
        return "lg"
    if d.get("pre"):
        return "final" if d.get("fin") else "mid"
    return "single" if d.get("fin") else "base"


def _qmap(xs, ys):
    xs = sorted(xs)
    ys = sorted(ys)

    def f(x):
        p = bisect.bisect_left(xs, x) / max(1, len(xs) - 1)
        p = min(1, p)
        idx = p * (len(ys) - 1)
        lo = int(idx)
        hi = min(len(ys) - 1, lo + 1)
        return ys[lo] + (ys[hi] - ys[lo]) * (idx - lo)
    return f


RED_MOVE_ALIAS = {"visegrip": "vicegrip", "highjumpkick": "hijumpkick", "feintattack": "faintattack", "smellingsalts": "smellingsalt"}


def red_move_rows():
    """Red's move table: normalised Red name -> (power, acc1, acc2, pp, crit, hits)."""
    names = redsrc.names_from_s("data/move/move_names.s", "MoveName")
    out = {}
    for d in redsrc.load("data/move/move_data.json"):
        nm = names.get(d["name"])
        if not nm and d["name"].startswith("MonsterCategory"):
            nm = re.sub(r"(?<!^)(?=[A-Z])", " ", d["name"][len("MonsterCategory"):])
        if not nm:
            continue
        out.setdefault(redsrc.norm(nm), (d["basePower"], d["accuracy1"], d["accuracy2"], d["basePP"], d.get("critChance", 0),
                                        d.get("numberOfChainedHits", 1)))
    return out


def build_pmd(dex, dexmoves):
    """PMD Red numbers for every species and move (gen_pmd.py): Red's own from the ROM, the rest laid out the same way."""
    red = red_records(dex)
    main5 = lambda b: [b[0], b[1], b[3], b[2], b[4]]          # hp atk def spa spd spe -> PMD order hp atk spa def spd
    bst = lambda k: sum(dex[k]["b"])
    curve = []
    for j in range(5):
        acc = np.zeros(100)
        n = 0
        for r in red.values():
            tot = sum(r["gains"][j])
            if tot <= 0:
                continue
            acc += np.concatenate([[0], np.cumsum(r["gains"][j])]) / tot
            n += 1
        curve.append([num(round(float(x), 4)) for x in (acc / n)])
    keys = sorted(red)
    QB1 = [_qmap([main5(dex[k]["b"])[j] for k in keys], [red[k]["b1"][j] for k in keys]) for j in range(5)]
    Q100 = [_qmap([main5(dex[k]["b"])[j] for k in keys], [red[k]["s100"][j] for k in keys]) for j in range(5)]
    QEY = _qmap([dex[k]["xp"] for k in keys], [red[k]["ey"] for k in keys])
    xp_tables, xp_index = [], {}

    def xpi(t):
        t = tuple(t)
        if t not in xp_index:
            xp_index[t] = len(xp_tables)
            xp_tables.append(list(t))
        return xp_index[t]

    enc = lambda gains: "".join("".join(chr(48 + g) for g in row) for row in gains)
    mon = {}
    for k, d in dex.items():
        if k in red:
            r = red[k]
            mon[k] = [*r["b1"], enc(r["gains"]), xpi(r["xp"]), r["ey"], r["rr"]]
            continue
        m = main5(d["b"])
        st = _stage(dex, k)
        b1 = [max(0 if j else 10, round(QB1[j](m[j]))) for j in range(5)]
        s100 = [max(b1[j] + 1, round(Q100[j](m[j]))) for j in range(5)]
        same = [x for x in keys if _stage(dex, x) == st] or keys
        near = min(same, key=lambda x: (abs(bst(x) - bst(k)), x))
        rr = -999 if st == "lg" else red[near]["rr"]
        mon[k] = [*b1, s100, xpi(red[near]["xp"]), max(1, round(QEY(d["xp"]))), rr]

    # moves: Red's where Red has the move, else main-series power/PP/accuracy mapped onto Red's scale
    MV = red_move_rows()
    rm = lambda k: MV.get(RED_MOVE_ALIAS.get(redsrc.norm(k), redsrc.norm(k)))
    pairs, ppairs, apairs = defaultdict(list), defaultdict(list), defaultdict(list)
    for k, v in dexmoves.items():
        m = rm(k)
        if not m:
            continue
        if v.get("p") and m[0] > 0 and m[5] == 1:
            pairs[v["p"]].append(m[0])
        ppairs[v["pp"]].append(m[3])
        if v.get("p") and m[0] > 0:
            apairs[min(100, v.get("a") or 100) if (v.get("a") or 0) < 999 else 999].append((m[1], m[2]))
    pk = sorted(pairs)
    pv = list(np.maximum.accumulate([float(np.median(pairs[p])) for p in pk]))
    pow_of = lambda p: max(1, round(float(np.interp(p, pk, pv))))
    pks = sorted(ppairs)
    pp_of = lambda pp: max(1, round(float(np.interp(pp, pks, [np.median(ppairs[x]) for x in pks]))))

    def acc_of(a):
        a = 999 if (a or 0) >= 999 else min(100, a or 100)
        if a == 999:
            return (125, 125)
        ks = sorted(x for x in apairs if x < 999)
        near = min(ks, key=lambda x: abs(x - a))
        lst = apairs[near]
        return (int(np.median([x[0] for x in lst])), int(np.median([x[1] for x in lst])))
    moves = {}
    for k, v in dexmoves.items():
        m = rm(k)
        if m:
            moves[k] = [m[0], m[1], m[2], m[3], m[4], 1]
        else:
            a1, a2 = acc_of(v.get("a"))
            if not v.get("p"):
                a1, a2 = (125, 125) if (v.get("a") or 999) >= 100 else (min(100, v["a"]), 125)
            moves[k] = [pow_of(v["p"]) if v.get("p") else 0, a1, a2, pp_of(v["pp"]), 12 if v.get("p") else 0, 0]
    return {"mon": js_order(mon), "curve": curve, "xp": xp_tables, "move": moves}


# ---------------------------------------------------------------- the prototype's runtime tables
def js_order(d):
    """Key order of a JavaScript object: integer-like keys ascending first, then the rest in insertion order."""
    isint = lambda k: k.isdigit() and (k == "0" or not k.startswith("0"))
    return {**{k: d[k] for k in sorted((k for k in d if isint(k)), key=int)}, **{k: v for k, v in d.items() if not isint(k)}}


PMD_PHYS = {"Normal", "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel"}   # Red splits by type


def build_moves(dexmoves, pmd):
    """MOVES as the prototype ran it: main-series descriptors with Red's power/accuracy/PP/crit numbers."""
    order = [k for k in T.MOVE_ORDER_HEAD if k in dexmoves] + [k for k in dexmoves if k not in T.MOVE_ORDER_HEAD]
    out = {}
    for k in order:
        M = json.loads(json.dumps(dexmoves[k]))
        d = pmd["move"].get(k)
        if d:
            M["mp"] = M.get("p")
            if M.get("p"):
                M["p"] = d[0]
            M["a"], M["a2"], M["pp"], M["critP"] = d[1], d[2], d[3], d[4]
            if M["c"] != "X":
                M["c"] = "P" if M["t"] in PMD_PHYS else "S"
            if M["mp"] is None:
                del M["mp"]
        out[k] = M
    return out


def build_species(pa, dex):
    """SPECIES as the prototype ran it (DEX + purple Kecleon + its Mega Evolutions)."""
    sp = {}
    for k in T.SPECIES_ORDER_HEAD + list(dex):
        if k in sp:
            continue
        src = dex["0352"] if k == "0352p" else dex[k]
        sp[k] = json.loads(json.dumps(src))
    sup = set(T.ABILITIES)
    for key, ident in T.MEGAS:
        base = key[:4]
        B = sp.get(base)
        if not B:
            continue
        pid = pa.pid_of[ident]
        mb, bb = pa.base_stats(pid), pa.base_stats(base.lstrip("0"))
        mul = [num(round(mb[0] / bb[0], 3)), num(round(mb[1] / bb[1], 3)), num(round(mb[3] / bb[3], 3)),
               num(round(mb[2] / bb[2], 3)), num(round(mb[4] / bb[4], 3))]
        ab = [a for _, a, h in sorted(pa.abilities[pid]) if not h][:1]
        suffix = " X" if ident.endswith("-x") else " Y" if ident.endswith("-y") else ""
        e = {"name": "Mega " + B["name"] + suffix, "types": pa.type_list(pid), "b": mb, "xp": B["xp"],
             "ab": ab if ab and ab[0] in sup else (B.get("ab") or []), "learn": B["learn"], "megaBase": base, "pre": base,
             "fin": True, "mul": mul}
        if B.get("lg"):
            e["lg"] = B["lg"]
        sp[key] = e
    return js_order(sp)


# ---------------------------------------------------------------- evolutions (gen_evo.py)
FRIEND_LV = 25
RED_STONE = {106: "upgrade", 107: "kingsrock", 108: "thunderstone", 109: "deepseascale", 110: "deepseatooth", 111: "sunstone",
             112: "moonstone", 113: "firestone", 114: "waterstone", 115: "metalcoat", 116: "leafstone", 117: "dragonscale"}
EITHER_ITEM = {983: "leaderscrest", 855: "crackedpot|chippedpot", 1013: "unremarkableteacup|masterpieceteacup",
               892: "scrollofdarkness|scrollofwaters",
               869: "strawberrysweet|berrysweet|lovesweet|starsweet|cloversweet|flowersweet|ribbonsweet"}


def build_evo(pa, dex):
    """[evolves into, level, how]: Red's rules for Red's Pokemon, the main series' (PokeAPI) for the rest.
    how: 'f' = friendship (at that level), <item id> = needs that item (a|b = either); level 0 alone = special."""
    def pa_how(to_i, strict=True):
        found = []
        for r in pa.evolution:
            if int(r["evolved_species_id"]) != to_i:
                continue
            if strict and (r["region_id"] or r["required_pokemon_form_id"] or r["evolved_pokemon_form_id"]):
                continue
            if r["minimum_happiness"] or r["minimum_affection"]:
                found.append((0, "f"))
                continue
            it = pa.items.get(r["trigger_item_id"]) if r["evolution_trigger_id"] == "3" else None
            held = pa.items.get(r["held_item_id"])
            if it:
                found.append((1, it.replace("-", "")))
            elif held:
                found.append((1, "sweet" if held.endswith("-sweet") else held.replace("-", "")))
            elif r["evolution_trigger_id"] == "2":
                found.append((2, "linkingcord"))
            elif r["evolution_trigger_id"] == "5":
                found.append((2, "sweet"))
        if to_i in EITHER_ITEM:
            return EITHER_ITEM[to_i]
        return min(found)[1] if found else pa_how(to_i, False) if strict else None

    def special(to, red_item=None):
        h = pa_how(int(to)) or ("linkingcord" if red_item == "link" else RED_STONE.get(red_item) if red_item else None)
        return [to, FRIEND_LV, "f"] if h == "f" else [to, 0, h] if h else [to, 0]

    mons = redsrc.load("data/monster/monster_data.json")
    mon_ids = redsrc.consts("include/constants/monster.h", "MONSTER_")
    item_ids = redsrc.consts("include/constants/item.h", "ITEM_")
    evo = defaultdict(list)
    red_done = set()
    for m in mons:
        d = m["dexInternal"][0]
        pe = m.get("preEvolution") or {}
        if not (1 <= d <= 386) or not pe.get("evolveType"):
            continue
        to = key_of(d)
        fd = mons[mon_ids[pe["evolveFrom"]]]["dexInternal"][0]     # Red numbers Munchlax 387: not a national dex number
        frm = key_of(fd) if 1 <= fd <= 386 else None
        if not frm or to not in dex or frm not in dex or to in red_done:
            continue
        red_done.add(to)
        t = pe["evolveType"]
        req = (m.get("evolutionRequirements") or {}).get("mainRequirement", 0)
        if t == "EVOLVE_TYPE_LEVEL" and int(req or 0) > 1:
            evo[frm].append([to, int(req)])
        elif t == "EVOLVE_TYPE_NONE":
            continue                                    # Shedinja appears on its own in Red
        else:
            evo[frm].append(special(to, item_ids.get(req) if t == "EVOLVE_TYPE_ITEM" else "link" if t == "EVOLVE_TYPE_LINK_CABLE" else None))
    best = {}
    for r in pa.evolution:
        to = int(r["evolved_species_id"])
        if to in best and best[to]["is_default"] == "1":
            continue
        best[to] = r
    for to_i, r in best.items():
        to = key_of(to_i)
        if to not in dex or to in red_done:
            continue
        frm_i = pa.species[str(to_i)]["evolves_from_species_id"]
        if not frm_i:
            continue
        frm = key_of(frm_i)
        if frm not in dex:
            continue
        lv = int(r["minimum_level"]) if (r["minimum_level"] and r["evolution_trigger_id"] == "1" and not r["minimum_happiness"]
                                         and not r["time_of_day"] and not r["known_move_id"] and not r["trigger_item_id"]) else 0
        if any(t[0] == to for t in evo[frm]):
            continue
        evo[frm].append([to, lv] if lv else special(to))
    late = {t[0] for v in evo.values() for t in v if len(t) == 2 and t[1] >= FRIEND_LV}
    for frm, v in evo.items():
        for t in v:
            if len(t) > 2 and t[2] == "f" and frm in late:
                t[1] = 36
    return js_order(dict(evo))


_built = None


def build_all():
    """{'DEX', 'DEXMOVES', 'SPECIES', 'MOVES', 'PMD', 'EVO', 'ITEMS'} like the prototype's tables (cached)."""
    global _built
    if _built is None:
        pa = PA()
        keys = species_keys(pa)
        dm = build_dexmoves(pa, keys)
        dex = build_dex(pa, dm)
        pmd = build_pmd(dex, dm)
        _built = {"DEX": dex, "DEXMOVES": dm, "SPECIES": build_species(pa, dex), "MOVES": build_moves(dm, pmd), "PMD": pmd,
                  "EVO": build_evo(pa, dex),
                  "ITEMS": common.load_json(os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto_items.json"))}
    return _built
