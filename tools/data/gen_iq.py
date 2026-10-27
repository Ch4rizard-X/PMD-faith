#!/usr/bin/env python3
"""Export PMD Red's IQ / tactics / gummi / Gulpin Link Shop data from the pret/pmd-red decomp
into game/data/iq.json.

Sources (pret/pmd-red):
  include/constants/iq_skill.h, include/constants/tactic.h, include/constants/type.h
  src/dungeon_data.c   gReqIQSkillPts, gReqTacticLvls, gTacticsTargetLeader, gTypeGummiIQBoost,
                       gUnknown_810A808 (belly filled by a gummi in a dungeon), g*IQReq (333)
  src/pokemon_3.c      sIQSkillGroups (mutually exclusive skill slots), SetDefaultIQSkills
  src/strings.c        gIQSkillNames, gIQSkillDescriptions, gTacticsNames, gTacticsDescriptions
  src/dungeon_strings.c gummi messages (dungeon), IQ skill learned message
  src/data/code_80227B8.h  gummi messages (town "Give Gummi")
  src/moves.c          DoesMoveCharge (charging moves cannot be linked)
  src/data/locale/gulpin_shop_usa.h  Gulpin's dialogue (awake + asleep)
  data/monster/monster_data.json  Red's species types (for the gummi table)

Red has no per-species IQ groups (that is Explorers): every Pokemon unlocks the same skill at the
same IQ, and skills sharing an sIQSkillGroups slot cannot be switched on together.
"""
import json, re, os, sys
sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402

RED = common.PMDRED
GAME = common.GAME


def read(p):
    with open(os.path.join(RED, p), encoding="utf-8") as f:
        return f.read()


def enum_list(src, name):
    body = re.search(r"enum\s+" + name + r"\s*\{(.*?)\}", src, re.S).group(1)
    out = []
    for line in body.split("\n"):
        line = line.split("//")[0].strip().rstrip(",")
        if line:
            out.append(line.split("=")[0].strip())
    return out


def c_table(src, name):
    """[KEY] = value entries of a designated-initialiser array."""
    m = re.search(re.escape(name) + r"\s*\[[^\]]*\]\s*=\s*\{(.*?)\n\};", src, re.S)
    return dict(re.findall(r"\[(\w+)\]\s*=\s*([^,\n]+),?", m.group(1)))


def c_strings(src, name):
    m = re.search(re.escape(name) + r"\s*\[[^\]]*\]\s*=\s*\{(.*?)\n\};", src, re.S)
    out = {}
    for k, v in re.findall(r"\[(\w+)\]\s*=\s*_\(\"((?:[^\"\\]|\\.)*)\"\)", m.group(1)):
        out[k] = v.replace("\\n", "\n")
    return out


def snake(s):
    s = s.lower().replace("é", "e").replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


iq_h = read("include/constants/iq_skill.h")
tac_h = read("include/constants/tactic.h")
dd = read("src/dungeon_data.c")
p3 = read("src/pokemon_3.c")
st = read("src/strings.c")
ds = read("src/dungeon_strings.c")

IQ_ENUM = enum_list(iq_h, "IQSkillID")
TAC_ENUM = enum_list(tac_h, "TacticID")
req_iq = c_table(dd, "gReqIQSkillPts")
groups = c_table(p3, "sIQSkillGroups")
iq_names = c_strings(st, "gIQSkillNames")
iq_desc = c_strings(st, "gIQSkillDescriptions")
tac_lv = c_table(dd, "gReqTacticLvls")
tac_leader = c_table(dd, "gTacticsTargetLeader")
tac_names = c_strings(st, "gTacticsNames")
tac_desc = c_strings(st, "gTacticsDescriptions")

skills = []
for i, e in enumerate(IQ_ENUM):
    if e in ("IQ_NONE", "NUM_IQ_SKILLS"):
        continue
    name = iq_names[e]
    skills.append({"id": snake(name), "red_id": i, "name": name, "desc": iq_desc[e],
                   "iq": int(req_iq[e]), "group": int(groups[e])})
by_enum = {e: snake(iq_names[e]) for e in IQ_ENUM if e in iq_names and e != "IQ_NONE"}

dflt = re.search(r"void SetDefaultIQSkills\(.*?\{(.*?)\n\}", p3, re.S).group(1)
default_on = [by_enum[x] for x in re.findall(r"SetIQSkill\(iq,\s*(IQ_\w+)\)", dflt) if x != "IQ_SELF_CURER"]

tactics = []
for i, e in enumerate(TAC_ENUM):
    if e == "NUM_TACTICS":
        continue
    name = tac_names[e].strip()
    tid = "unused" if e == "TACTIC_UNUSED" else snake(name)
    tactics.append({"id": tid, "red_id": i, "name": name, "desc": tac_desc.get(e, ""), "level": int(tac_lv[e]),
                    "target_leader": tac_leader[e].strip() == "TRUE", "unused": e in ("TACTIC_ALL_FOR_ONE", "TACTIC_GROUP_SAFETY", "TACTIC_UNUSED")})

# ---- gummis
TYPES = ["None", "Normal", "Fire", "Water", "Grass", "Electric", "Ice", "Fighting", "Poison", "Ground", "Flying",
         "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Dark", "Steel"]
# ITEM_WHITE_GUMMI .. ITEM_SILVER_GUMMI, gummi_index = id - ITEM_WHITE_GUMMI + 1 (column 0 unused)
GUMMI_ITEMS = ["whitegummi", "redgummi", "bluegummi", "grassgummi", "yellowgummi", "cleargummi", "orangegummi",
               "pinkgummi", "browngummi", "skygummi", "goldgummi", "greengummi", "graygummi", "purplegummi",
               "royalgummi", "blackgummi", "silvergummi"]


def type_table(name):
    m = re.search(re.escape(name) + r"\s*\[NUM_TYPES\]\[NUMBER_OF_GUMMIS\]\s*=\s*\{(.*?)\n\};", dd, re.S)
    out = {}
    for k, row in re.findall(r"\[TYPE_(\w+)\]\s*=\s*\{([^}]*)\}", m.group(1)):
        vals = [int(x.strip(), 0) for x in row.split(",") if x.strip()]
        out[k.capitalize()] = vals
    return out


iq_tab = type_table("gTypeGummiIQBoost")
belly_tab = type_table("gUnknown_810A808")
gummi_iq = {}
gummi_belly = {}
for t in TYPES[1:]:
    gummi_iq[t] = {TYPES[j]: iq_tab[t][j] for j in range(1, 18)}
    gummi_belly[t] = {TYPES[j]: belly_tab[t][j] for j in range(1, 18)}
gummis = {GUMMI_ITEMS[j]: TYPES[j + 1] for j in range(17)}

ult = {}
for k, v in re.findall(r"const s16 g(\w+)IQReq\s*=\s*(\d+);", dd):
    ult[{"FrenzyPlant": "Frenzy Plant", "HydroCannon": "Hydro Cannon", "BlastBurn": "Blast Burn", "VoltTackle": "Volt Tackle"}[k]] = int(v)

mv = read("src/moves.c")
charge_body = re.search(r"bool8 DoesMoveCharge\(u16 move\)\s*\{(.*?)\n\}", mv, re.S).group(1)
MOVE_FIX = {"SOLARBEAM": "Solarbeam"}
charge = []
for x in re.findall(r"MOVE_(\w+)\)", charge_body):
    charge.append(MOVE_FIX.get(x, " ".join(w.capitalize() for w in x.split("_"))))

# ---- messages
def one(name, src):
    return re.search(re.escape(name) + r"\s*=\s*_\(\"((?:[^\"\\]|\\.)*)\"\)", src).group(1).replace("\\n", "\n")


def arr(name, src):
    m = re.search(re.escape(name) + r"\[\]\s*=\s*\{(.*?)\};", src, re.S)
    return [s.replace("\\n", "\n") for s in re.findall(r"_\(\"((?:[^\"\\]|\\.)*)\"\)", m.group(1))]


town = read("src/data/code_80227B8.h")


def town_str(name):
    m = re.search(r"static const u8 " + name + r"\[\]\s*=\s*_\((.*?)\);", town, re.S)
    return "".join(re.findall(r"\"((?:[^\"\\]|\\.)*)\"", m.group(1))).replace("\\n", "\n")


messages = {
    "dungeon_no_change": one("gUnknown_80FD644", ds),
    "dungeon_taste": arr("gUnknown_80FD648", ds),
    "dungeon_iq": arr("gUnknown_80FD6E8", ds),
    "dungeon_learned": one("gUnknown_80FEAC4", ds),
    "town_taste": [town_str("sFmtGummiBigFav"), town_str("sFmtGummiFav"), town_str("sFmtGummiOkay"), town_str("sFmtGummiSatisfied")],
    "town_learned": town_str("sFmtIQHelpedLearn"),
    "town_not_hungry": town_str("sDoesNotAppearHungry"),
    "town_stat": {"all": town_str("sFmtPlusEverything"), "atk": town_str("sFmtPlusAtk"), "spa": town_str("sFmtPlusSpAtk"),
                  "def": town_str("sFmtPlusDef"), "spd": town_str("sFmtPlusSpDef")},
    "town_no_gummis": town_str("sNoGummis"),
}

# ---- Gulpin dialogue
gl = read("src/data/locale/gulpin_shop_usa.h")
gulpin = {"awake": [], "asleep": []}
for mode, tag in (("awake", "AWAKE"), ("asleep", "ASLEEP")):
    for i in range(25):
        m = re.search(r"#define GULP_" + tag + r"_DLG_%02d \(_\((.*?)\)\)\n" % i, gl, re.S)
        gulpin[mode].append("".join(re.findall(r"\"((?:[^\"\\]|\\.)*)\"", m.group(1))).replace("\\n", "\n"))

# ---- species types (Red's own typing for the gummi table)
md = json.load(open(os.path.join(RED, "data/monster/monster_data.json")))
species = json.load(open(os.path.join(GAME, "data/species.json")))
red_types = {}
for i, mon in enumerate(md):
    if i == 0:
        continue
    dex = int(mon["dexInternal"][0])
    ts = [t.replace("TYPE_", "").capitalize() for t in mon["types"]]
    ts = [t for t in ts if t != "None"]
    key = "%04d" % dex
    if key in species and key not in red_types and dex > 0:
        red_types[key] = ts

out = {
    "source": "pret/pmd-red (see gen_iq.py)",
    "iq_max": 999, "iq_min": 1,
    "skills": skills,
    "default_on": default_on,
    "tactics": tactics,
    "default_tactic": "lets_go_together",
    "types": TYPES[1:],
    "gummis": gummis,
    "gummi_iq": gummi_iq,
    "gummi_belly": gummi_belly,
    "ultimate_moves_iq": ult,
    "charge_moves": charge,
    "link_fee": 150,
    "no_remember": ["0386", "0446"],      # Deoxys (DLG_16 "special Pokemon"), Munchlax (sub_808E218 returns 0)
    "messages": messages,
    "gulpin": gulpin,
    "red_types": red_types,
}
dst = os.path.join(GAME, "data/iq.json")
with open(dst, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print("wrote", dst, len(skills), "skills", len(tactics), "tactics", len(red_types), "red species types")

# Explorers of Sky add-on skills: gen_iq_sky.py (run after this by build.py) merges them on top.
