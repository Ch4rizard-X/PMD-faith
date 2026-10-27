# Builds res://data/menu_text.json (Red's menu strings) from the pret/pmd-red decomp.
import json, re
import os, sys
sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
R = common.PMDRED + os.sep
G = common.GAME + os.sep

def unesc(s):
    return bytes(s, "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")

def s_labels(path):
    out = {}
    cur = None
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^(\w+):\s*$", line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r'^\s*\.string "(.*)"\s*$', line)
        if m and cur:
            out[cur] = out.get(cur, "") + unesc(m.group(1)).replace("\0", "")
    return out

def c_table(text, name):
    i = text.index(name)
    j = text.index("};", i)
    body = text[i:j]
    out = {}
    for m in re.finditer(r'\[(\w+)\]\s*=\s*(?:\{\s*)?_\("((?:[^"\\]|\\.)*)"\)(?:\s*,\s*_\("((?:[^"\\]|\\.)*)"\))?', body):
        out[m.group(1)] = [unesc(m.group(2))] + ([unesc(m.group(3))] if m.group(3) is not None else [])
    return out

def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())

out = {}
# ---- moves: description + range name, keyed by the move's name
names = s_labels(R + "data/move/move_names.s")
mdata = json.load(open(R + "data/move/move_data.json"))
strings = open(R + "src/strings.c", encoding="utf-8").read()
ranges = {k: v[0] for k, v in c_table(strings, "gRangeNames").items()}
moves = {}
for e in mdata:
    nm = names.get(e["name"], "")
    if not nm:
        continue
    moves[nm] = {"desc": names.get(e["description"], ""), "range": ranges.get(e["rangeID"], "")}
out["moves"] = moves
# ---- abilities
abn = c_table(strings, "gAbilityNames")
abd = c_table(strings, "gAbilityDescriptions")
ab = {}
for k, v in abn.items():
    ab[norm(k.replace("ABILITY_", ""))] = {"name": v[0], "desc": abd.get(k, [""])[0]}
out["abilities"] = ab
# ---- statuses (gStatusDescriptions: name, description)
st = c_table(strings, "gStatusDescriptions")
out["statuses"] = {k: {"name": re.sub(r"\{[^}]*\}", "", v[0]).strip(), "desc": v[1] if len(v) > 1 else ""} for k, v in st.items()}
# ---- species categories
mn = s_labels(R + "data/monster/monster_names.s")
mons = json.load(open(R + "data/monster/monster_data.json"))
cat = {}
for i, e in enumerate(mons):
    c = mn.get(e.get("category", ""), "")
    if c:
        cat["%04d" % i] = c
out["categories"] = cat
# ---- traps and stairs (dungeon_strings.c)
ds = open(R + "src/dungeon_strings.c", encoding="utf-8").read()
tn = c_table(ds, "[TRAP_TRIP_TRAP] = _(\"Trip Trap\")".split(" =")[0] if False else "_(\"Trip Trap\")")
traps = {}
# names
for m in re.finditer(r'\[TRAP_(\w+)\]\s*=\s*_\("([^"]*)"\)', ds):
    key, val = m.group(1), unesc(m.group(2))
    k = {"WHIRLWIND_TRAP": "gust", "PP_ZERO_TRAP": "ppzero", "WONDER_TILE": "wonder", "SPIKE_TRAP": "spiked"}.get(key, key.replace("_TRAP", "").lower())
    d = traps.setdefault(k, {})
    if "\n" in val or len(val) > 24:
        d["desc"] = val
    else:
        d["name"] = val
out["traps"] = traps
out["stairs_desc"] = "Stairs leading to the next floor.\nIf you are on the final floor, you will\nescape from the dungeon."
json.dump(out, open(G + "data/menu_text.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(moves), len(ab), len(out["statuses"]), len(cat), traps.keys())
print(moves.get("Iron Tail"), ab.get("blaze"), out["statuses"]["1"], cat.get("0004"), traps.get("wonder"))
