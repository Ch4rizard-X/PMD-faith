#!/usr/bin/env python3
"""Generate the Red-ID data tables embedded in game/scripts/core/wonder_mail.gd (between the
'# >>> GENERATED' / '# <<< GENERATED' markers) from the pret/pmd-red decomp.

Everything here is what ValidateWonderMail (src/code_80958E8.c) needs, by Red id:
  dungeon_info.c   sDungeonFloorCount, sFloorMissionDifficulty_* / sDungeonMissionDifficulty, gUnknown_8107828
  dungeon_data.c   gInvalidDungeonIDs, gInvalidItemIDs, gFriendAreaSettings (UNLOCK_WONDER_MAIL)
  data/dungeon/dungeon_data.json  gDungeons[].maxItemsAllowed
  items.c          gUnknown_8108F64 (item can appear in dungeon bit table)
  data/item/item_data.json        item categories (thrown items)
  pokemon_mail_pre.h gUnknown_80E80E0 (species banned from mail)
  constants/monster.h + monster_data.json + monster_names.s  Red monster id -> national dex key
Usage: python3 gen_wondermail.py [pmdred] [game]
"""
import json, os, re, sys
sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402

RED = common.PMDRED
GAME = common.GAME
OUT = os.path.join(GAME, "scripts/core/wonder_mail.gd")


def src(p):
    return open(os.path.join(RED, p), encoding="utf-8", errors="replace").read()


def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def defines(path, prefix):
    out = {}
    for m in re.finditer(r"#define (%s\w+)\s+(0x[0-9A-Fa-f]+|\d+)\b" % prefix, src(path)):
        out.setdefault(m.group(1), int(m.group(2), 0))
    return out


norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
MON = defines("include/constants/monster.h", "MONSTER_")
MON["MONSTER_MAX"] = MON["MONSTER_RAYQUAZA_CUTSCENE"] + 1
ITEM = defines("include/constants/item.h", "ITEM_")
NUM_ITEMS = ITEM["ITEM_G_MACHINE_8"] + 1
DUN = {m.group(1): int(m.group(2)) for m in re.finditer(r"(DUNGEON_\w+) = (\d+)", src("include/constants/dungeon.h"))}
FA = defines("include/constants/friend_area.h", "FRIEND_AREA_")

# --------------------------------------------------------------- dungeons
dinfo = strip_comments(src("src/dungeon_info.c"))


def table_u8(name):
    m = re.search(r"%s\[\] = \{(.*?)\};" % name, dinfo, re.S)
    return {DUN[mm.group(1)]: int(mm.group(2)) for mm in re.finditer(r"\[(\w+)\]\s*=\s*(\d+)", m.group(1))}


floor_count = table_u8("sDungeonFloorCount")
NUM = DUN["DUNGEON_OUT_ON_RESCUE"]  # 63
fc = [floor_count[i] for i in range(NUM + 1)]

m = re.search(r"gUnknown_8107828\[\] =\s*\{(.*?)\};", dinfo, re.S)
no_job = [[DUN[a], int(b)] for a, b in re.findall(r"\.id = (\w+), \.floor = (\d+)", m.group(1))]
no_job = [p for p in no_job if p[0] < NUM]

arrs = {}
for mm in re.finditer(r"(sFloorMissionDifficulty_\w+)\[\] = \{(.*?)\};", dinfo, re.S):
    a = {}
    for e in re.finditer(r"\[(\d+)(?:\s*\.\.\.\s*(\d+))?\]\s*=\s*(\d+)", mm.group(2)):
        lo, hi, v = int(e.group(1)), int(e.group(2) or e.group(1)), int(e.group(3))
        for i in range(lo, hi + 1):
            a[i] = v
    arrs[mm.group(1)] = a
m = re.search(r"sDungeonMissionDifficulty\[\] = \{(.*?)\};", dinfo, re.S)
diff = [[0] * fc[i] for i in range(NUM)]
for nm, an in re.findall(r"\[(\w+)\] = (\w+)", m.group(1)):
    i = DUN[nm]
    if i < NUM:
        diff[i] = [arrs[an].get(f, 0) for f in range(fc[i])]

ddata = strip_comments(src("src/dungeon_data.c"))
m = re.search(r"gInvalidDungeonIDs\[\d+\] =\s*\{(.*?)\};", ddata, re.S)
invalid_dungeons = [DUN[n] for n in re.findall(r"(DUNGEON_\w+)", m.group(1)) if DUN[n] < NUM]
m = re.search(r"gInvalidItemIDs\[\d+\] =\s*\{(.*?)\};", ddata, re.S)
invalid_items = [ITEM[n] for n in re.findall(r"\b(ITEM_\w+)", m.group(1))]
wm_areas = [FA[n] for n in re.findall(r"\[(FRIEND_AREA_\w+)\] = \{[^}]*unlock_condition = UNLOCK_WONDER_MAIL", ddata)]

gd = json.load(open(os.path.join(RED, "data/dungeon/dungeon_data.json")))
max_items = [int(gd[i]["maxItemsAllowed"]) for i in range(NUM)]

itc = strip_comments(src("src/items.c"))
m = re.search(r"gUnknown_8108F64\[UNK_8108F64_ARR_COUNT\]\[32\] = \{(.*?)\n\};", itc, re.S)
lut_rows = ["".join("%02x" % int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]+)", row)) for row in re.findall(r"\{([^{}]*)\}", m.group(1))]
assert len(lut_rows) == 64 and all(len(r) == 64 for r in lut_rows)

idata = json.load(open(os.path.join(RED, "data/item/item_data.json")))
thrown = [i for i, it in enumerate(idata[:NUM_ITEMS]) if it["category"] in ("CATEGORY_THROWN_LINE", "CATEGORY_THROWN_ARC")]

pre = strip_comments(src("src/data/pokemon_mail_pre.h"))
m = re.search(r"gUnknown_80E80E0\[\d+\] = \{(.*?)\};", pre, re.S)
banned = [MON[n] for n in re.findall(r"(MONSTER_\w+)", m.group(1)) if n != "MONSTER_NONE"]

# --------------------------------------------------------------- species: Red monster id -> dex key
species = json.load(open(os.path.join(GAME, "data/species.json")))
by_norm = {"farfetchd": "0083"}
for k in sorted(species):
    if len(k) == 4:
        by_norm.setdefault(norm(species[k]["name"]), k)
s = src("data/monster/monster_names.s")
mnames = {}
for mm in re.finditer(r"\n(MonsterName\w+):\s*\n\.(?:string|asciz) \"([^\"\\]*)", s):
    mnames[mm.group(1)] = re.sub(r"\{[^}]*\}", "", mm.group(2)).strip()
mdata = json.load(open(os.path.join(RED, "data/monster/monster_data.json")))
FORCED = {"MONSTER_FARFETCHD": "0083", "MONSTER_NIDORAN_F": "0029", "MONSTER_NIDORAN_M": "0032", "MONSTER_DECOY": "", "MONSTER_STATUE": "", "MONSTER_NONE": ""}
by_id = {}
for n, v in MON.items():
    by_id.setdefault(v, n)
red_species = []
for i in range(MON["MONSTER_MAX"]):
    n = by_id.get(i, "")
    if n in FORCED:
        red_species.append(FORCED[n]); continue
    k = ""
    if n.startswith("MONSTER_UNOWN"):
        k = "0201"
    elif n.startswith("MONSTER_CASTFORM"):
        k = "0351"
    elif n.startswith("MONSTER_DEOXYS"):
        k = "0386"
    elif i < len(mdata):
        k = by_norm.get(norm(mnames.get(mdata[i]["name"], "")), "")
    red_species.append(k)
missing = [(i, by_id.get(i)) for i, k in enumerate(red_species) if k == "" and i not in (0, MON["MONSTER_DECOY"], MON["MONSTER_STATUE"])]
if missing:
    print("WARNING unmapped species:", missing)
base = list(range(MON["MONSTER_MAX"]))
for n, v in MON.items():
    if n.startswith("MONSTER_UNOWN_") and n != "MONSTER_UNOWN_A":
        base[v] = MON["MONSTER_UNOWN"]
for n in ("MONSTER_CASTFORM_SNOWY", "MONSTER_CASTFORM_SUNNY", "MONSTER_CASTFORM_RAINY"):
    base[MON[n]] = MON["MONSTER_CASTFORM"]
for n in ("MONSTER_DEOXYS_ATTACK", "MONSTER_DEOXYS_DEFENSE", "MONSTER_DEOXYS_SPEED"):
    base[MON[n]] = MON["MONSTER_DEOXYS_NORMAL"]
base[MON["MONSTER_RAYQUAZA_CUTSCENE"]] = MON["MONSTER_RAYQUAZA"]
not_base = [i for i in range(len(base)) if base[i] != i]

# --------------------------------------------------------------- emit
def arr(a):
    return "[" + ", ".join(json.dumps(x) for x in a) + "]"


def wrap(name, items, per=20, typ=""):
    lines = []
    for i in range(0, len(items), per):
        lines.append("\t" + ", ".join(json.dumps(x) for x in items[i:i + per]) + ",")
    return "const %s%s := [\n%s\n]\n" % (name, typ, "\n".join(lines))


g = []
g.append("# >>> GENERATED by gen_wondermail.py from pret/pmd-red - do not edit by hand\n")
g.append("const RED_NUM_DUNGEONS := %d            # DUNGEON_OUT_ON_RESCUE\n" % NUM)
g.append("const RED_MONSTER_MAX := %d\n" % MON["MONSTER_MAX"])
g.append("const RED_NUM_ITEMS := %d               # NUMBER_OF_ITEM_IDS\n" % NUM_ITEMS)
g.append("const RED_ITEM_POKE := %d\nconst RED_ITEM_USED_TM := %d\n" % (ITEM["ITEM_POKE"], ITEM["ITEM_TM_USED_TM"]))
g.append("const RED_FRIEND_AREA_MAX := %d          # FRIEND_AREA_FINAL_ISLAND\n" % FA["FRIEND_AREA_FINAL_ISLAND"])
g.append("## sDungeonFloorCount (includes floor 0; real floors 1..count-1)\n" + wrap("RED_FLOOR_COUNT", fc[:NUM], 21))
g.append("## gDungeons[].maxItemsAllowed\n" + wrap("RED_MAX_ITEMS", max_items, 21))
g.append("## gInvalidDungeonIDs\nconst RED_INVALID_DUNGEONS := %s\n" % arr(invalid_dungeons))
g.append("## gUnknown_8107828 (no job on these [dungeon, floor])\n" + wrap("RED_NO_JOB_FLOORS", no_job, 10))
g.append("## sDungeonMissionDifficulty[dungeon][floor]\nconst RED_DIFFICULTY := [\n" + "\n".join("\t" + arr(d) + "," for d in diff) + "\n]\n")
g.append("## gUnknown_8108F64: item can be found in dungeon (32 bytes per dungeon as hex)\nconst RED_ITEM_LUT := [\n" + "\n".join('\t"%s",' % r for r in lut_rows) + "\n]\n")
g.append("## CATEGORY_THROWN_LINE / CATEGORY_THROWN_ARC item ids\n" + wrap("RED_THROWN_ITEMS", thrown, 25))
g.append("## gInvalidItemIDs\nconst RED_INVALID_ITEMS := %s\n" % arr(invalid_items))
g.append("## gFriendAreaSettings with UNLOCK_WONDER_MAIL\nconst RED_WM_FRIEND_AREAS := %s\n" % arr(wm_areas))
g.append("## gUnknown_80E80E0: species never allowed in mail\nconst RED_BANNED_SPECIES := %s\n" % arr(banned))
g.append("## species ids for which GetBaseSpecies(id) != id\nconst RED_NOT_BASE_SPECIES := %s\n" % arr(not_base))
g.append("## Red monster id -> national dex species key (\"\" = none)\n" + wrap("RED_SPECIES", red_species, 16))
items_j = json.load(open(os.path.join(GAME, "data/items.json")))
inames = {}
for mm in re.finditer(r"\n(ItemName\w+):\s*\n\.(?:string|asciz) \"([^\"\\\\]*)", src("data/item/item_names.s")):
    inames[mm.group(1)] = re.sub(r"\{[^}]*\}", "", mm.group(2)).strip()
by_red = {int(v["red_id"]): k for k, v in items_j.items() if v.get("red_id")}
by_iname = {norm(v.get("name", "")): k for k, v in items_j.items()}
item_keys = []
for i in range(NUM_ITEMS):
    k = by_red.get(i, "")
    if not k and i > 0:
        k = by_iname.get(norm(inames.get(idata[i]["name"], "")), "")
        if not k:
            print("WARNING unmapped item", i, idata[i]["name"])
    item_keys.append(k)
g.append("## Red item id -> data/items.json key\n" + wrap("RED_ITEMS", item_keys, 10))
fa_keys = list(json.load(open(os.path.join(GAME, "data/friend_areas.json")))["areas"].keys())
assert len(fa_keys) == FA["FRIEND_AREA_FINAL_ISLAND"], len(fa_keys)
g.append("## friend area index (1..57) -> data/friend_areas.json key (same order as Red's FRIEND_AREA_*)\n" + wrap("RED_FRIEND_AREAS", [""] + fa_keys, 8))
g.append("# <<< GENERATED\n")
block = "".join(g)

if os.path.exists(OUT):
    cur = open(OUT, encoding="utf-8").read()
    a = cur.find("# >>> GENERATED")
    b = cur.find("# <<< GENERATED")
    if a >= 0 and b >= 0:
        b = cur.index("\n", b) + 1
        cur = cur[:a] + block + cur[b:]
        open(OUT, "w", encoding="utf-8").write(cur)
        print("updated", OUT)
        sys.exit(0)
open(common.p(common.TMP, "wondermail_tables.gd.txt"), "w").write(block)
print("wrote wondermail_tables.gd.txt (paste into wonder_mail.gd)")
