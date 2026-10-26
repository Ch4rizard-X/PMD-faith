#!/usr/bin/env python3
"""Red's evolution requirements (pmdred_full/data/monster/monster_data.json: preEvolution / evolutionRequirements,
used by pokemon_evolution.c SetMonEvolveStatus) -> game/data/red_evo.json
  {pre_species_key: [[target_key, type, main, additional], ...]}
type: "level" (main = level), "iq" (main = IQ), "item" (main = item key), "link" (EVOLVE_TYPE_LINK_CABLE), "none"
additional: 0 none, 4 Link Cable, 5 Atk>Def, 6 Atk<Def, 7 Atk=Def, 8 Sun Ribbon, 9 Lunar Ribbon, 10 Beauty Scarf,
            11 Wurmple even, 12 Wurmple odd
"""
import json, re
RED = "/tmp/claude-0/pmdred_full"
G = "/tmp/claude-0/pmd1/game"
mons = json.load(open(f"{RED}/data/monster/monster_data.json"))
extra = json.load(open(f"{G}/data/ground/extra.json"))
red_mon = extra["red_mon"]
items = json.load(open(f"{G}/data/items.json"))
by_red = {int(v["red_id"]): k for k, v in items.items() if v.get("red_id") is not None}
consts = {}
for m in re.finditer(r"#define (MONSTER_\w+) (\d+)", open(f"{RED}/include/constants/monster.h").read()):
    consts[m.group(1)] = int(m.group(2))
for m in re.finditer(r"#define (ITEM_\w+) (\d+)", open(f"{RED}/include/constants/item.h").read()):
    consts[m.group(1)] = int(m.group(2))
out = {}
for rid, e in enumerate(mons):
    p = e.get("preEvolution") or {}
    t = p.get("evolveType")
    if not t or t == "EVOLVE_TYPE_NONE":
        continue
    pre = red_mon.get(str(consts[p["evolveFrom"]]))
    tgt = red_mon.get(str(rid))
    if not pre or not tgt:
        continue
    r = e.get("evolutionRequirements") or {}
    main = r.get("mainRequirement", 0)
    kind = {"EVOLVE_TYPE_LEVEL": "level", "EVOLVE_TYPE_IQ": "iq", "EVOLVE_TYPE_ITEM": "item", "EVOLVE_TYPE_LINK_CABLE": "link"}[t]
    if kind == "item":
        main = by_red.get(consts.get(main, -1), str(main)[5:].replace("_", "").lower())
    else:
        main = int(main) if not isinstance(main, str) else consts.get(main, 0)
    out.setdefault(pre, []).append([tgt, kind, main, int(r.get("additionalRequirement", 0) or 0)])
json.dump(out, open(f"{G}/data/red_evo.json", "w"), indent=0)
print(len(out), "pre-evolutions;", out.get("0025"), out.get("0133"), out.get("0290"), out.get("0236"), out.get("0265"))
