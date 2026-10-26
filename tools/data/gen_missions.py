#!/usr/bin/env python3
"""Export PMD Red's rescue-job (Pelipper board / mailbox) tables from the pret/pmd-red decomp
into game/data/missions.json for scripts/core/missions.gd.

Sources (all in the decomp):
  src/code_80958E8.c          GenerateMailJobInfo / GenerateMailJobDungeonInfo / GeneratePelipperJobs (logic is
                              re-implemented in missions.gd; only tables are exported here)
  src/code_803C1B4.c          difficulty -> letter / rank points / money; reward item roll
  src/dungeon_info.c          sDungeonFloorCount, sFloorMissionDifficulty_*, gUnknown_8107828 (no-job floors),
                              sRandomItemsSet1..15 (mission reward item sets, indexed by difficulty)
  src/items.c                 gUnknown_8108F64 (per-dungeon "item can appear here" bit table)
  src/dungeon_data.c          gInvalidItemIDs, gFriendAreaSettings (UNLOCK_WONDER_MAIL areas)
  src/code_80A26CC.c          sScriptDungeonData (.unk11 = dungeon may host jobs once conquered)
  src/data/pokemon_mail_pre.h rank points, banned species, pair / item tables, fixed strings
  src/data/pokemon_mail.h     difficulty letters, title / description text pools, parent/friend pair texts
  src/data/thank_you_messages.h, src/mission_reward.c, src/dungeon_strings.c, src/strings.c, rescue_team_info.c

Usage:  python3 gen_missions.py [path/to/pmdred] [path/to/game]
"""
import json
import os
import re
import sys

RED = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/pmdred"
GAME = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "game")


def src(p):
    with open(os.path.join(RED, p), encoding="utf-8") as f:
        return f.read()


def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


# ----------------------------------------------------------------------------- Red text -> BBCode
COLORS = {"YELLOW": "#ffdc4a", "YELLOW_N": "#ffdc4a", "GREEN": "#7fff7f", "GREEN_RAW": "#7fff7f",
          "CYAN": "#7fe0ff", "CYAN_G": "#7fe0ff", "RED": "#ff8070", "DEFAULT": "#ffffff"}


def red_text(s):
    s = re.sub(r"\{COLOR (\w+)\}", lambda m: "[color=%s]" % COLORS.get(m.group(1), "#ffffff"), s)
    s = s.replace("{RESET}", "[/color]")
    s = s.replace("{POKE}", "Poké").replace("{STAR_BULLET}", "*").replace("〜", "~").replace("♪", "")
    s = s.replace("{CENTER_ALIGN}", "")
    s = s.replace("{EXTRA_MSG}", "\f")            # page break inside one message
    return s


def c_strings(body):
    """Concatenate the C string literals in body (handles _("a" "b"))."""
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
    return "".join(parts).replace("\\n", "\n").replace('\\"', '"')


def str_arrays(text):
    """name -> [strings] for `const u8 * const NAME[N] = { _("..."), ... };`"""
    out = {}
    for m in re.finditer(r"const u8 \* ?const (\w+)\[[^\]]*\] = \{(.*?)\n\};", text, re.S):
        items = re.findall(r'_\(((?:\s*"(?:[^"\\]|\\.)*"\s*)+)\)', m.group(2))
        out[m.group(1)] = [red_text(c_strings(i)) for i in items]
    return out


def str_singles(text):
    """name -> string for `... u8 NAME[] = _("...");` (possibly multi-line)."""
    out = {}
    for m in re.finditer(r"u8 (\w+)\[\]\s*=\s*_\(((?:\s*\"(?:[^\"\\]|\\.)*\"\s*)+)\);", text):
        out[m.group(1)] = red_text(c_strings(m.group(2)))
    for m in re.finditer(r"u8 \*const (\w+) = _\(((?:\s*\"(?:[^\"\\]|\\.)*\"\s*)+)\);", text):
        out[m.group(1)] = red_text(c_strings(m.group(2)))
    return out


# ----------------------------------------------------------------------------- constants
def defines(path, prefix):
    out = {}
    for m in re.finditer(r"#define (%s\w+)\s+(\d+)" % prefix, src(path)):
        out[m.group(1)] = int(m.group(2))
    return out


MON = defines("include/constants/monster.h", "MONSTER_")
ITEM = defines("include/constants/item.h", "ITEM_")
CATS = defines("include/constants/item.h", "CATEGORY_")
NUM_CATS = 12
NUM_ITEMS = ITEM["ITEM_G_MACHINE_8"] + 1
DUN = {m.group(1): int(m.group(2)) for m in re.finditer(r"(DUNGEON_\w+) = (\d+)", src("include/constants/dungeon.h"))}
FA = defines("include/constants/friend_area.h", "FRIEND_AREA_")

# ----------------------------------------------------------------------------- game-side keys
species = json.load(open(os.path.join(GAME, "data/species.json")))
items = json.load(open(os.path.join(GAME, "data/items.json")))
dungeons = json.load(open(os.path.join(GAME, "data/dungeons.json")))["dungeons"]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


_by_name = {}
for k in sorted(species):
    if len(k) == 4:
        _by_name.setdefault(norm(species[k]["name"]), k)
SPECIAL_MON = {"MONSTER_NIDORAN_F": "0029", "MONSTER_NIDORAN_M": "0032", "MONSTER_UNOWN_A": "0201",
               "MONSTER_UNOWN": "0201", "MONSTER_DEOXYS_NORMAL": "0386", "MONSTER_CASTFORM": "0351"}


def mon_key(name):
    if name in SPECIAL_MON:
        return SPECIAL_MON[name]
    k = _by_name.get(norm(name[len("MONSTER_"):]))
    return k


ITEM_BY_RED = {int(v["red_id"]): k for k, v in items.items() if v.get("red_id")}
CAT_BY_RED = {int(v["red_id"]): v.get("red_cat", "") for k, v in items.items() if v.get("red_id")}


def item_key(name):
    i = ITEM.get(name)
    return ITEM_BY_RED.get(i) if i is not None else None


DKEY_BY_INDEX = {int(v["index"]): k for k, v in dungeons.items()}

# ----------------------------------------------------------------------------- dungeon tables
dinfo = strip_comments(src("src/dungeon_info.c"))


def table_u8(name):
    m = re.search(r"%s\[\] = \{(.*?)\};" % name, dinfo, re.S)
    return {mm.group(1): int(mm.group(2)) for mm in re.finditer(r"\[(\w+)\]\s*=\s*(\d+)", m.group(1))}


floor_count = table_u8("sDungeonFloorCount")
excluded = {}
m = re.search(r"gUnknown_8107828\[\] =\s*\{(.*?)\};", dinfo, re.S)
for mm in re.finditer(r"\.id = (\w+), \.floor = (\d+)", m.group(1)):
    excluded.setdefault(mm.group(1), []).append(int(mm.group(2)))

diff_arrays = {}
for mm in re.finditer(r"sFloorMissionDifficulty_(\w+)\[\] = \{(.*?)\};", dinfo, re.S):
    arr = {}
    for e in re.finditer(r"\[(\d+)(?: \.\.\. (\d+))?\] = (\d+)", mm.group(2)):
        a, b, v = int(e.group(1)), int(e.group(2) or e.group(1)), int(e.group(3))
        for i in range(a, b + 1):
            arr[i] = v
    diff_arrays["sFloorMissionDifficulty_" + mm.group(1)] = [arr.get(i, 0) for i in range(max(arr) + 1)]
m = re.search(r"sDungeonMissionDifficulty\[\] = \{(.*?)\};", dinfo, re.S)
diff_by_dungeon = {mm.group(1): diff_arrays[mm.group(2)] for mm in re.finditer(r"\[(\w+)\] = (\w+)", m.group(1))}

# job dungeons: script dungeons with .unk11 = TRUE, minus ids 43..46 (Wonder-Mail-only dungeons)
sdd = src("src/code_80A26CC.c")
job_ids = set()
for mm in re.finditer(r"\.dungeonID = (\w+),.*?\.unk11 = (\w+),", sdd, re.S):
    if mm.group(2) == "TRUE" and mm.group(1) in DUN:
        job_ids.add(DUN[mm.group(1)])
job_ids -= {43, 44, 45, 46}

# item-can-appear bit table
itc = strip_comments(src("src/items.c"))
m = re.search(r"gUnknown_8108F64\[UNK_8108F64_ARR_COUNT\]\[32\] = \{(.*?)\n\};", itc, re.S)
lut_rows = [[int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]+)", row)] for row in re.findall(r"\{([^{}]*)\}", m.group(1))]

ddata = strip_comments(src("src/dungeon_data.c"))
m = re.search(r"gInvalidItemIDs\[\d+\] =\s*\{(.*?)\};", ddata, re.S)
invalid_items = [n for n in re.findall(r"(ITEM_\w+)", m.group(1))]
invalid_ids = {ITEM[n] for n in invalid_items if n in ITEM}

out_dungeons = {}
for name, idx in DUN.items():
    if idx >= 63 or idx not in DKEY_BY_INDEX or name not in floor_count:
        continue
    key = DKEY_BY_INDEX[idx]
    lut = []
    if idx < len(lut_rows):
        row = lut_rows[idx]
        for i in range(1, NUM_ITEMS):
            if (row[i >> 3] >> (i & 7)) & 1 and i in ITEM_BY_RED:
                lut.append(ITEM_BY_RED[i])
    out_dungeons[key] = {
        "red_index": idx,
        "red_floor_count": floor_count[name],     # Red counts floor 0 too: real floors = count - 1
        "difficulty": diff_by_dungeon.get(name, []),
        "no_job_floors": excluded.get(name, []),
        "items": lut,
        "jobs": idx in job_ids,
    }

# ----------------------------------------------------------------------------- reward item sets
ODDS_RE = re.compile(r"ODDS\(([\d.]+)\)")


def odds(x):
    v = int(x * 100)
    return v + (1 if (int(x * 100) & 0xFFFF) != (int((x + 0.001) * 100) & 0xFFFF) else 0)


def sym(n):
    if n in CATS:
        return CATS[n]
    return ITEM[n]


def parse_set(body):
    raw = []
    SKIP = 30000
    for mm in re.finditer(r"(FIRST_CATEGORY_CHANCE|NEXT_CHANCE|SKIP_CATEGORY_TO_ITEM|SKIP_REMAINING_ITEMS|SKIP)\s*\(([^()]*(?:\([^()]*\))?[^()]*)\)", body):
        op, args = mm.group(1), [a.strip() for a in mm.group(2).split(",")]
        if op == "FIRST_CATEGORY_CHANCE":
            raw += [SKIP + sym(args[0]), odds(float(ODDS_RE.match(args[1]).group(1)))]
        elif op == "NEXT_CHANCE":
            raw.append(odds(float(ODDS_RE.match(args[1]).group(1))))
        elif op == "SKIP_CATEGORY_TO_ITEM":
            raw.append(NUM_CATS - 1 - sym(args[0]) + sym(args[1]) + SKIP)
        elif op == "SKIP":
            raw.append(sym(args[1]) - sym(args[0]) - 1 + SKIP)
        elif op == "SKIP_REMAINING_ITEMS":
            raw.append(NUM_ITEMS - sym(args[0]) - 1 + SKIP)
    vals = []
    for v in raw:                       # GetRandomItemForSet's expansion
        if v >= SKIP:
            vals += [0] * (v - SKIP)
        else:
            vals.append(v)
    vals = (vals + [0] * (NUM_CATS + NUM_ITEMS))[:NUM_CATS + NUM_ITEMS]
    catv, itemv = vals[:NUM_CATS], vals[NUM_CATS:]
    cat_names = {v: k[len("CATEGORY_"):].lower() for k, v in CATS.items() if k != "CATEGORY_7"}
    # cumulative thresholds (pick: first non-zero value >= rand(0..9998)) -> weights
    cats, prev = [], 0
    for c in range(NUM_CATS):
        if catv[c]:
            w = max(0, min(catv[c], 9999) - prev)
            prev = max(prev, min(catv[c], 9999))
            if w:
                cats.append([cat_names.get(c, str(c)), w])
    per = {}
    for c in range(NUM_CATS):
        lst, prev = [], 0
        for i in range(NUM_ITEMS):
            if itemv[i] and CAT_BY_RED.get(i) == cat_names.get(c):
                w = max(0, min(itemv[i], 9999) - prev)
                prev = max(prev, min(itemv[i], 9999))
                if w and i in ITEM_BY_RED:
                    lst.append([ITEM_BY_RED[i], w])
        if lst:
            per[cat_names[c]] = lst
    return {"cats": cats, "items": per}


item_sets = {}
for mm in re.finditer(r"sRandomItemsSet(\d+)\[\] = \{(.*?)\};", dinfo, re.S):
    n = int(mm.group(1))
    if 1 <= n <= 15:
        item_sets[str(n)] = parse_set(mm.group(2))

# ----------------------------------------------------------------------------- mail data
pre = strip_comments(src("src/data/pokemon_mail_pre.h"))
mail = src("src/data/pokemon_mail.h")
mail_nc = strip_comments(mail)
m = re.search(r"gUnknown_80E80A0\[16\] = \{(.*?)\};", pre, re.S)
rank_points = [int(x) for x in re.findall(r"\d+", m.group(1))]


def mon_list(name):
    m = re.search(r"%s\[\d+\] = \{(.*?)\};" % name, pre, re.S)
    return [k for k in (mon_key(n) for n in re.findall(r"(MONSTER_\w+)", m.group(1)) if n != "MONSTER_NONE") if k]


def pair_list(name, text=pre):
    m = re.search(r"%s\[\d+\] = \{(.*?)\n\};" % name, text, re.S)
    return re.findall(r"\{\s*(\w+),\s*(\w+)(?:,\s*(\w+))?(?:,\s*(\w+))?\s*\}", m.group(1))


singles = {}
singles.update(str_singles(pre))
singles.update(str_singles(mail))
arrays = str_arrays(mail)

banned = mon_list("gUnknown_80E80E0")
banned_pre = mon_list("gUnknown_80E8126")
lovers = [[mon_key(a), mon_key(b)] for a, b, _, _ in pair_list("gUnknown_80E8168")]
evo_items = [[mon_key(a), item_key(b)] for a, b, _, _ in pair_list("gUnknown_80E8180")]
gummi_prefs = [[mon_key(a), item_key(b)] for a, b, _, _ in pair_list("gUnknown_80E81D4") if mon_key(a)]   # alt forms have no key
parent_child = [[mon_key(a), mon_key(b), singles[t]] for a, b, t, _ in pair_list("gUnknown_80E9920", mail_nc)]
friend_pairs = [[mon_key(a), mon_key(b), singles[h], singles[t]] for a, b, h, t in pair_list("gUnknown_80E9F8C", mail_nc)]

text = {
    "rescue_title": arrays["gUnknown_80E8C98"],        # title, rescue client      [b2 % 15]
    "rescue_desc1": arrays["gUnknown_80E8DE4"],        # description line 1        [b2 % 13]
    "rescue_desc2": arrays["gUnknown_80E8FB0"],        # description line 2        [b3 % 13]
    "target_title": arrays["gUnknown_80E910C"],        # title, rescue target      [b2 % 10] (%s = target)
    "target_desc1": arrays["gUnknown_80E91D4"],        # [b2 % 45]
    "target_desc2": arrays["gUnknown_80E9820"],        # [b3 % 10]
    "escort_title": arrays["gUnknown_80EAE5C"],        # [b2 % 4]
    "escort_desc1": arrays["gUnknown_80EAEB8"],        # [b2 % 20]
    "escort_desc2": arrays["gUnknown_80EB198"],        # [b3 % 4]
    "love_desc1": arrays["gUnknown_80EB220"],          # escort to my love [b2 % 6]
    "love_desc2": arrays["gUnknown_80EB2F0"],          # [b3 % 6]
    "item_desc1": arrays["gUnknown_80EB3F8"],          # find / deliver [b2 % 22]
    "item_desc2": arrays["gUnknown_80EB72C"],          # [b3 % 22]
    "difficulty": ["E", "D", "C", "B", "A", "S", "*"],
    "difficulty_bbcode": arrays["gMissionRankText"],
    "reward_fmt": arrays["gMissionRewardText"],
    "status": arrays["sUnknown_80E8BCC"],              # "", Suspend, Take Job, Done
    "deliver_title": singles["gUnknown_80E8830"],
    "find_title": singles["gUnknown_80E8848"],
    "child_title": singles["gUnknown_80E885C"],
    "love_title": singles["gUnknown_80E886C"],
    "near": singles["gUnknown_80E8884"],
    "description": singles["gUnknown_80E888C"],
    "evo_desc": singles["gUnknown_80E8968"],
    "gummi_desc": singles["gUnknown_80E89B0"],
    "client": singles["gUnknown_80E8AC8"],
    "objective": singles["gUnknown_80E8AE0"],
    "obj_deliver": singles["gUnknown_80E8AFC"],
    "obj_find": singles["gUnknown_80E8B10"],
    "obj_rescue": singles["gUnknown_80E8B20"],
    "obj_escort": singles["gUnknown_80E8B2C"],
    "obj_target": singles["gUnknown_80E8B40"],
    "place": singles["gPlaceText"],
    "difficulty_label": singles["gDifficultyText"],
    "reward": singles["gRewardText"],
}

# thank-you / reward / in-dungeon strings
ty = str_singles(src("src/data/thank_you_messages.h"))
mr = str_singles(src("src/mission_reward.c"))
ds = str_singles(src("src/dungeon_strings.c"))
text.update({
    "thanks_rescue": ty["sThanksForRescuingMe"].strip(),
    "thanks_target": ty["sThanksForRescuingThem"].strip(),
    "thanks_escort": ty["sThanksForEscortingMe"].strip(),
    "thanks_deliver": ty["sThanksForDelivering"].strip(),
    "thanks_find": ty["sThanksForGetting"].strip(),
    "reward_money": mr["gUnknown_80E0434"].strip(),
    "got_money": mr["gUnknown_80E045C"],
    "got_money_team": mr["gUnknown_80E0484"],
    "reward_area": mr["gUnknown_80E04B4"].strip(),
    "area_owned": mr["gUnknown_80E04F4"],
    "got_area": mr["gUnknown_80E05C0"],
    "got_area_team": mr["gUnknown_80E05FC"],
    "reward_item": mr["gUnknown_80E0640"].strip(),
    "got_points": mr["gUnknown_80E0670"],
    "rank_up": mr["gUnknown_80E06A8"],
    "dj_badge": ds["gUnknown_80FA260"],
    "dj_delivered": ds["gUnknown_80FA2B0"],
    "dj_found_rescue": ds["gUnknown_80FA2F0"],
    "dj_found_deliver": ds["gUnknown_80FA32C"],
    "dj_done_leave": ds["gUnknown_80FA36C"],
    "dj_really_leave": ds["gUnknown_80FA394"],
    "dj_continue": ds["gUnknown_80FA3B8"],
    "dj_no_item": ds["gUnknown_80FA448"],
    "dj_cant_talk": ds["gUnknown_80FA464"],
    "dj_escorted": ds["gUnknown_80FA4D4"],
    "dj_not_around": ds["gUnknown_80FA500"],
    "dj_cant_complete": ds["gUnknown_80FA52C"],
})

# ranks (rescue_team_info.c + strings.c)
rti = src("src/rescue_team_info.c")
m = re.search(r"sRescueRankMaxPoints\[MAX_TEAM_RANKS\] = \{(.*?)\};", rti, re.S)
rank_max = [int(x) for x in re.findall(r"= (\d+)", m.group(1))]
strs = src("src/strings.c")
m = re.search(r"gRescueTeamRanks\[MAX_TEAM_RANKS\] = \{(.*?)\};", strs, re.S)
rank_names = re.findall(r'_\("([^"]*)"\)', m.group(1))
ranks = []
lo = 0
for nm, mx in zip(rank_names, rank_max):
    ranks.append([nm.replace(" Rank", ""), lo])
    lo = mx

# friend areas offered as Wonder Mail rewards (mailbox jobs only)
m = re.search(r"gFriendAreaNames\[FRIEND_AREA_COUNT\] = \{(.*?)\};", strs, re.S)
fa_names = {mm.group(1): mm.group(2) for mm in re.finditer(r"\[(FRIEND_AREA_\w+)\]\s*= _\(\"([^\"]*)\"\)", m.group(1))}
wm_areas = []
for mm in re.finditer(r"\[(FRIEND_AREA_\w+)\] = \{[^}]*unlock_condition = UNLOCK_WONDER_MAIL", ddata):
    wm_areas.append(norm(fa_names[mm.group(1)]))

out = {
    "_source": "pret/pmd-red via gen_missions.py",
    "ranks": ranks,                              # [name, min points]
    "rank_points": rank_points,                  # by mission difficulty 0..15
    "mission_types": ["rescue", "target", "escort", "find", "deliver", "escort", "target", "rescue"],
    "max_jobs": 8,
    "mailbox_slots": 4,
    "fallback_dungeons": [DKEY_BY_INDEX[0], DKEY_BY_INDEX[1]],
    "dungeons": out_dungeons,
    "item_sets": item_sets,                      # reward item set N = mission difficulty N
    "invalid_reward_items": [ITEM_BY_RED[i] for i in sorted(invalid_ids) if i in ITEM_BY_RED],
    "banned_species": banned,
    "banned_species_pregame": banned_pre,
    "lover_pairs": lovers,
    "evo_items": evo_items,
    "gummi_prefs": gummi_prefs,
    "parent_child": parent_child,
    "friend_pairs": friend_pairs,
    "wonder_mail_friend_areas": wm_areas,
    "text": text,
}
dst = os.path.join(GAME, "data/missions.json")
with open(dst, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print("wrote", dst, "dungeons:", len(out_dungeons), "job dungeons:", sum(1 for d in out_dungeons.values() if d["jobs"]),
      "item sets:", len(item_sets), "gummi prefs:", len(gummi_prefs), "friend pairs:", len(friend_pairs))
