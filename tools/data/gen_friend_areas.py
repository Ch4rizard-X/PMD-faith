#!/usr/bin/env python3
"""All 57 PMD Red Friend Areas -> game/data/friend_areas.json (port of the prototype's gen_friend.py).
  price / unlock / capacity: pmd-red src/dungeon_data.c gFriendAreaSettings
  name / description:        src/strings.c gFriendAreaNames / gFriendAreaDescriptions
  music:                     each area's ground map (src/data/ground/ground_data_hNNpMM_station.h)
  residents:                 Red's own (monster_data friendArea); Pokemon not in Red go where most of Red's Pokemon of their
                             type live (families together, areas filled in proportion to Red's capacity, newer legendaries
                             to the legendary areas, a few themed families placed by hand).
"cap" is raised to the number of residents where the area holds more Pokemon than in Red ("red_cap" keeps Red's)."""
import os
import re
import sys
from collections import Counter, defaultdict

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
import proto  # noqa: E402
import redsrc  # noqa: E402

HOW = {"UNLOCK_SHOP_STORY": "Shop Story", "UNLOCK_SHOP_POST_GAME": "Shop Post Game", "UNLOCK_WONDER_MAIL": "Wonder Mail",
       "UNLOCK_LEGENDARY_REQUEST": "Legendary Request"}
LEGACY = {"Mist-Rise Forest": "mistrise", "Flyaway Forest": "flyaway", "Wild Plains": "wildplains"}
# a few families that clearly belong to one themed area
THEME = {"ancientrelic": "Cranidos Shieldon Tirtouga Archen Tyrunt Amaura Dracozolt Arctozolt Dracovish Arctovish Bronzor Golett Sigilyph",
         "tadpolepond": "Tympole Froakie Croagunk Wiglett",
         "frigidcavern": "Frigibax Snom Cubchoo Bergmite Cetoddle Vanillite",
         "mushroomforest": "Foongus Morelull Toedscool Brute Bonnet Phantump Pumpkaboo",
         "turtleshellpond": "Turtwig Tirtouga Turtonator Chewtle Piplup",
         "crater": "Chimchar Litwick Larvesta Sizzlipede Charcadet Heatmor Salandit",
         "echocave": "Woobat Noibat Roggenrola Carbink Diglett",
         "rubadubriver": "Buizel Ducklett Bidoof Wingull Panpour Sobble",
         "peanutswamp": "Stunky Skrelp Mareanie Shellos",
         "decrepitlab": "Rotom Porygon Klink Varoom Magnemite Tadbulb",
         "powerplant": "Shinx Blitzle Tynamo Helioptile Charjabug Pawmi",
         "overgrownforest": "Snivy Sewaddle Rowlet Fomantis Grookey Sprigatito Bounsweet",
         "wildplains": "Lillipup Patrat Yungoos Skwovet Lechonk Bunnelby",
         "beauplains": "Flabébé Cottonee Petilil Gossifleur Fidough Smoliv",
         "treasuresea": "Finneon Frillish Wailmer Dhelmise Finizen Bruxish",
         "mtdeepgreen": "Riolu Pancham Hawlucha Mienfoo Crabrawler"}


def c_strings(text, table):
    i = text.index(table)
    body = text[i:text.index("};", i)]
    out = {}
    for m in re.finditer(r"\[(FRIEND_AREA_\w+)\]\s*=\s*_\(((?:\s*\"(?:[^\"\\]|\\.)*\")+)\s*\)", body):
        out[m.group(1)] = "".join(re.findall(r"\"((?:[^\"\\]|\\.)*)\"", m.group(2)))
    return out


def main():
    dex = proto.build_all()["DEX"]
    fa_enum = redsrc.consts("include/constants/friend_area.h", "FRIEND_AREA_")
    enum_by_idx = {v: k for k, v in fa_enum.items() if k != "FRIEND_AREA_COUNT"}
    mus, n = {}, 0
    for line in redsrc.read("include/constants/bg_music.h").split("\n"):
        m = re.match(r"\s*(MUS_\w+)\s*(?:=\s*(\d+))?,", line)
        if m:
            n = int(m.group(2)) if m.group(2) else n + 1
            mus[m.group(1)] = n
    gdir = redsrc.path("src/data/ground")
    hmaps = sorted({re.search(r"(h\d+p\d+)", f).group(1) for f in os.listdir(gdir) if re.search(r"h\d+p\d+", f)})
    song = []
    for h in hmaps:
        s = re.findall(r"MUS_\w+", redsrc.read(f"src/data/ground/ground_data_{h}_station.h"))
        song.append(mus[s[0]] if s else None)
    strings = redsrc.read("src/strings.c")
    names = c_strings(strings, "gFriendAreaNames[")
    descs = c_strings(strings, "gFriendAreaDescriptions[")
    settings = {}
    src = redsrc.read("src/dungeon_data.c")
    body = src[src.index("gFriendAreaSettings[FRIEND_AREA_COUNT]"):]
    for m in re.finditer(r"\[(FRIEND_AREA_\w+)\]\s*=\s*\{\s*\.num_pokemon\s*=\s*(\d+),\s*\.unlock_condition\s*=\s*(\w+),\s*\.price\s*=\s*(\d+)", body):
        settings[m.group(1)] = (int(m.group(2)), HOW[m.group(3)], int(m.group(4)))
    count = len(enum_by_idx) - 1
    assert len(hmaps) == count == 57, (len(hmaps), count)
    areas, by_enum = {}, {}
    for i in range(1, count + 1):
        e = enum_by_idx[i]
        name = names[e]
        key = LEGACY.get(name) or re.sub(r"[^a-z0-9]", "", name.lower())
        cap, how, price = settings[e]
        areas[key] = {"name": name, "price": price, "how": how, "cap": cap, "desc": descs[e].replace("\\n", " "),
                      "song": song[i - 1], "img": None, "species": []}
        by_enum[e] = key

    # ---- Red's residents
    red_area = {}
    for m in redsrc.load("data/monster/monster_data.json"):
        d = m["dexInternal"][0]
        if 1 <= d <= 386 and m.get("friendArea") in by_enum:
            red_area.setdefault("%04d" % d, by_enum[m["friendArea"]])
    # ---- newer Pokemon
    LEG_AREAS = [k for k, a in areas.items() if a["how"] == "Legendary Request" and a["cap"] <= 3 or a["cap"] <= 3]
    aff = {k: Counter() for k in areas}
    for sp, k in red_area.items():
        t = dex[sp]["types"]
        aff[k][t[0]] += 2
        for x in t[1:]:
            aff[k][x] += 1
    for k in aff:
        tot = sum(aff[k].values()) or 1
        for t in aff[k]:
            aff[k][t] /= tot

    def root(sp):
        seen = set()
        while dex[sp].get("pre") and dex[sp]["pre"] in dex and sp not in seen:
            seen.add(sp)
            sp = dex[sp]["pre"]
        return sp
    fam = defaultdict(list)
    for sp in dex:
        fam[root(sp)].append(sp)
    for k in areas:
        areas[k]["species"] = [sp for sp, a in red_area.items() if a == k]
    normal = [k for k in areas if k not in LEG_AREAS]
    new_total = sum(1 for sp in dex if sp not in red_area)
    cap_total = sum(areas[k]["cap"] for k in normal)
    target = {k: areas[k]["cap"] / cap_total * new_total for k in normal}
    load = Counter()

    def score(members, k):
        sc = 0
        for sp in members:
            t = dex[sp]["types"]
            sc += 2 * aff[k][t[0]] + sum(aff[k][x] for x in t[1:])
        return sc / len(members)
    theme_of = {}
    for k, nm in THEME.items():
        for x in nm.split():
            theme_of[x.lower()] = k
    plan = []
    for members in sorted(fam.values(), key=len, reverse=True):
        new = [sp for sp in members if sp not in red_area]
        if not new:
            continue
        redm = [red_area[sp] for sp in members if sp in red_area]
        th = next((theme_of[dex[sp]["name"].lower()] for sp in members if dex[sp]["name"].lower() in theme_of), None)
        if redm:
            k = Counter(redm).most_common(1)[0][0]
        elif any(dex[sp].get("lg") for sp in new):
            k = max(LEG_AREAS, key=lambda a: (score(new, a), -len(areas[a]["species"])))
        elif th and th in areas:
            k = th
        else:
            plan.append(new)
            continue
        areas[k]["species"].extend(new)
        if k in target:
            load[k] += len(new)
    for new in plan:
        ranked = sorted(normal, key=lambda a: -score(new, a))
        room = [a for a in ranked[:10] if load[a] + len(new) <= target[a] * 1.1 + 1]
        k = room[0] if room else min(ranked[:12], key=lambda a: (load[a] + len(new)) / target[a])
        areas[k]["species"].extend(new)
        load[k] += len(new)
    for a in areas.values():
        if len(a["species"]) > a["cap"]:
            a["red_cap"] = a["cap"]
            a["cap"] = len(a["species"])
    out = {"areas": areas, "species": {sp: k for k, a in areas.items() for sp in a["species"]}}
    common.save_json(os.path.join(common.DATA, "friend_areas.json"), out)
    print("friend areas", len(areas), "residents", len(out["species"]))


if __name__ == "__main__":
    main()
