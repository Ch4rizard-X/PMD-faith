#!/usr/bin/env python3
"""Extra tables the ground engine needs, pulled from the pmd-red decomp -> game/data/ground/extra.json.

C tables are copied out of their source files by name and compiled on the host (so every enum/macro resolves);
the few tables that only exist as raw bytes in data/*.s are parsed here.
  dungeons      sScriptDungeonData (script dungeon -> maps, getout script, DUNGEON_ id, rescue id)
  rescue_to_script  sRescueToScriptDungeonIdTable
  map_to_dungeon    sMapToDungeonTable (ground maps drawn with a dungeon tileset)
  local_vars    sLocalScriptVarInfo
  fa_maps       sMapIdToFriendAreaIdTable  [map, friend area]
  story_missions sStoryMissionText (text, flag1, flag2)
  lives_types   gGroundLivesTypeData_811E63C [type, species, w, h]
  object_types  gGroundObjectTypes [type, w, h]
  object_kinds  gGroundObjectKinds [u0, u2, file]
  effect_types  gGroundEffectTypes (first 64) [type, w, h]
  enums: dungeons (DUNGEON_*), rescue dungeons, friend areas, monsters, items, ground places
"""
import json, os, re, subprocess, sys

DEC = "/tmp/claude-0/pmdred_full"
OUT = "/tmp/claude-0/pmd1/game/data/ground/extra.json"
WORK = "/tmp/claude-0/-home-claude/gsextra"
os.makedirs(WORK, exist_ok=True)


def src(p):
    t = open(os.path.join(DEC, p), encoding="utf-8", errors="replace").read()
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r'^((?:[^"\n/]|"(?:[^"\\\n]|\\.)*"|/(?!/))*)//[^\n]*', r"\1", t, flags=re.M)


def grab(text, name):
    """'static const T name[...] = { ... };' -> the full declaration text."""
    m = re.search(r"(?:static\s+)?const\s+[\w\s\*]+?\b%s\s*\[[^\]]*\]\s*=\s*\{" % re.escape(name), text)
    if not m:
        sys.exit("table not found: " + name)
    i = m.end() - 1
    depth = 0
    q = None
    j = i
    while True:
        c = text[j]
        if q:
            if c == "\\":
                j += 1
            elif c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    decl = text[m.start():j + 1] + ";"
    return re.sub(r"^static\s+", "", decl)


tables = []
tables.append(grab(src("src/code_80A26CC.c"), "sScriptDungeonData"))
tables.append(grab(src("src/code_80A26CC.c"), "sRescueToScriptDungeonIdTable"))
gm = src("src/ground_map.c")
ms = re.search(r"struct MapToDungeonStruct\s*\{.*?\};", gm, re.S).group(0)
tables.append(grab(gm, "sMapToDungeonTable"))
ef = src("src/data/event_flag.h")
tables.append(grab(ef, "sLocalScriptVarInfo"))
mf = re.search(r"struct MapIdToFriendAreaIdStruct\s*\{.*?\};", ef, re.S)
tables.append(grab(ef, "sMapIdToFriendAreaIdTable"))
rs = src("src/rescue_scenario.c")
mt = re.search(r"typedef struct MissionText\s*\{.*?\}\s*MissionText;", rs, re.S).group(0)
tables.append(grab(rs, "sStoryMissionText"))
gsd = src("src/ground_sprite_data.c")
tables.append(grab(gsd, "gGroundObjectKinds"))

C = r'''
#include "global.h"
#include "globaldata.h"
#include "code_80A26CC.h"
#include "script_vars_info.h"
#include "constants/ground_map.h"
#include "constants/dungeon.h"
#include "constants/rescue_dungeon_id.h"
#include "constants/friend_area.h"
#include "rescue_scenario.h"
#include "event_flag.h"
#include "ground_sprite_data.h"
#include <stdio.h>
%(structs)s
%(tables)s
#define N(a) (int)(sizeof(a)/sizeof(a[0]))
static void s(FILE *f, const char *t) { if (!t) { fputs("null", f); return; } fputc('"', f);
  for (const unsigned char *p = (const unsigned char *)t; *p; p++) { if (*p=='"'||*p=='\\') fputc('\\', f); if (*p=='\n') { fputs("\\n", f); continue; } fputc(*p, f); } fputc('"', f); }
int main(void) {
  FILE *f = fopen("extra_c.json", "w");
  fputs("{\"dungeons\":[", f);
  for (int i = 0; i < N(sScriptDungeonData); i++) { const DungeonInfo *d = &sScriptDungeonData[i];
    fprintf(f, "%%s{\"map1\":%%d,\"map2\":%%d,\"map3\":%%d,\"script1\":%%d,\"script2\":%%d,\"script3\":%%d,\"dungeon\":%%d,\"rescue\":%%d,\"u11\":%%d}",
      i ? ",\n" : "", d->mapID1, d->mapID2, d->mapID3, d->scriptID1, d->scriptID2, d->scriptID3, d->dungeonID, d->rescueDungeonID, d->unk11); }
  fputs("],\n\"rescue_to_script\":[", f);
  for (int i = 0; i < N(sRescueToScriptDungeonIdTable); i++) fprintf(f, "%%s%%d", i ? "," : "", sRescueToScriptDungeonIdTable[i]);
  fputs("],\n\"map_to_dungeon\":[", f);
  for (int i = 0; i < N(sMapToDungeonTable); i++) fprintf(f, "%%s[%%d,%%d,%%d]", i ? "," : "", sMapToDungeonTable[i].id, sMapToDungeonTable[i].loc.id, sMapToDungeonTable[i].loc.floor);
  fputs("],\n\"local_vars\":[", f);
  for (int i = 0; i < N(sLocalScriptVarInfo); i++) { const struct ScriptVarInfo *v = &sLocalScriptVarInfo[i];
    fprintf(f, "%%s{\"type\":%%d,\"off\":%%d,\"bit\":%%d,\"len\":%%d,\"def\":%%d}", i ? "," : "", v->type, v->bufOffset, v->bitOffset, v->arrayLen, v->defaultValue); }
  fputs("],\n\"fa_maps\":[", f);
  for (int i = 0; i < N(sMapIdToFriendAreaIdTable); i++) fprintf(f, "%%s[%%d,%%d]", i ? "," : "", sMapIdToFriendAreaIdTable[i].mapId, sMapIdToFriendAreaIdTable[i].friendAreaId);
  fputs("],\n\"story_missions\":[", f);
  for (int i = 0; i < N(sStoryMissionText); i++) { fputs(i ? ",[" : "[", f); s(f, (const char *)sStoryMissionText[i].text);
    fprintf(f, ",%%d,%%d]", sStoryMissionText[i].cutsceneFlag1, sStoryMissionText[i].cutsceneFlag2); }
  fputs("],\n\"object_kinds\":[", f);
  for (int i = 0; i < N(gGroundObjectKinds); i++) { fprintf(f, "%%s[%%d,%%d,", i ? "," : "", gGroundObjectKinds[i].unk0, gGroundObjectKinds[i].unk2);
    s(f, gGroundObjectKinds[i].fileName); fputc(']', f); }
  fputs("]}\n", f); fclose(f); return 0; }
'''
structs = ms + "\n" + mf.group(0) + "\n" + mt
open(os.path.join(WORK, "x.c"), "w").write(C % {"structs": structs, "tables": "\n".join(tables)})
CF = ["-w", "-O0", "-iquote", DEC + "/include", "-iquote", DEC, "-D_(x)=x", "-D__(x)=x"]
r = subprocess.run(["gcc"] + CF + [os.path.join(WORK, "x.c"), "-o", os.path.join(WORK, "x")], capture_output=True, text=True)
if r.returncode:
    sys.exit(r.stderr[:4000])
subprocess.run([os.path.join(WORK, "x")], cwd=WORK, check=True)
extra = json.loads(open(os.path.join(WORK, "extra_c.json"), "rb").read().decode("utf-8", "replace"))


# ---------------------------------------------------------------- raw byte tables in data/*.s
def asm_bytes(label, text):
    """Bytes of a table in a .s file; .4byte pointers become 4 bytes (0xFF marker, value dropped)."""
    i = text.index(label + ":")
    out = []
    for line in text[i:].splitlines()[1:]:
        line = line.split("@")[0].strip()
        if not line:
            continue
        if line.startswith(".global") or (line.endswith(":") and not line.startswith(".")):
            break
        if line.startswith(".byte"):
            out += [int(x, 0) for x in line[5:].split(",")]
        elif line.startswith(".4byte"):
            out += [0, 0, 0, 0]
        elif line.startswith(".string") or line.startswith(".align"):
            break
    return out


s3 = src("data/data_8115F5C_3_.s")
b = asm_bytes("gGroundLivesTypeData_811E63C", s3)
lives = []
for k in range(0, len(b) - 11, 12):
    e = b[k:k + 12]
    t = e[0] | (e[1] << 8)
    sp = e[2] | (e[3] << 8)
    lives.append([t - 65536 if t > 32767 else t, sp, e[8], e[9]])
extra["lives_types"] = lives
b = asm_bytes("gGroundObjectTypes", s3)
extra["object_types"] = [[(b[k] | (b[k + 1] << 8)), b[k + 2], b[k + 3]] for k in range(0, len(b) - 3, 4)][:70]
b = asm_bytes("gGroundEffectTypes", s3)
extra["effect_types"] = [[(b[k] | (b[k + 1] << 8)), b[k + 2], b[k + 3]] for k in range(0, min(len(b), 256) - 3, 4)]


# ---------------------------------------------------------------- enums
def parse_enum(path, enum_name=None):
    t = src(path)
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    m = re.search(r"enum\s+%s\s*\{(.*?)\}" % enum_name, t, re.S) if enum_name else re.search(r"enum\s*\w*\s*\{(.*?)\}", t, re.S)
    out, v, env = {}, -1, {}
    for item in m.group(1).split(","):
        item = item.strip()
        if not item or item.startswith("#"):
            continue
        if "=" in item:
            n, e = [x.strip() for x in item.split("=", 1)]
            try:
                v = int(eval(e, {}, env))
            except Exception:
                v += 1
        else:
            n = item
            v += 1
        env[n] = v
        out[str(v)] = n if str(v) not in out else out[str(v)]
    return out


def parse_defines(path, prefix):
    out = {}
    for m in re.finditer(r"#define\s+(%s\w+)\s+(-?(?:0x[0-9a-fA-F]+|\d+))\b" % prefix, src(path)):
        out.setdefault(str(int(m.group(2), 0)), m.group(1))
    return out


extra["enums"] = {
    "dungeons": parse_enum("include/constants/dungeon.h"),
    "rescue": parse_enum("include/constants/rescue_dungeon_id.h"),
    "friend_areas": parse_defines("include/constants/friend_area.h", "FRIEND_AREA_"),
    "places": parse_enum("include/ground_place.h") if os.path.exists(DEC + "/include/ground_place.h") else {},
}
# ---------------------------------------------------------------- Red monster id -> our species key
def names_from_s(path, prefix):
    t = open(path, encoding="utf8", errors="replace").read()
    out = {}
    for m in re.finditer(r"\n(" + prefix + r"\w+):\s*\n\.string \"([^\"\\\\]*)", t):
        out[m.group(1)] = re.sub(r"\{[^}]*\}", "", m.group(2)).strip()
    return out


norm = lambda x: re.sub(r"[^a-z0-9]", "", x.lower())
SP = json.load(open("/tmp/claude-0/pmd1/game/data/species.json"))
by_name = {}
for k, v in SP.items():
    if len(k) == 4 and k < "1000":
        by_name.setdefault(norm(v["name"]), k)
mnames = names_from_s(DEC + "/data/monster/monster_names.s", "MonsterName")
mdata = json.load(open(DEC + "/data/monster/monster_data.json"))
red_mon = {}
for i, d in enumerate(mdata):
    nm = mnames.get(d["name"], "")
    k = by_name.get(norm(nm))
    if not k:
        low = norm(nm)
        for base in ["unown", "castform", "deoxys", "rayquaza"]:
            if low.startswith(base):
                k = by_name.get(base)
    if k:
        red_mon[str(i)] = k
extra["red_mon"] = red_mon
json.dump(extra, open(OUT, "w"), separators=(",", ":"), ensure_ascii=False)
print("dungeons", len(extra["dungeons"]), "lives_types", len(lives), "object_types", len(extra["object_types"]),
      "fa_maps", len(extra["fa_maps"]), "map_to_dungeon", len(extra["map_to_dungeon"]))
