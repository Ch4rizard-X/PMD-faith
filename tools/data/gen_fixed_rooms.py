#!/usr/bin/env python3
"""Extract Red Rescue Team's fixed rooms (boss arenas, item vaults) and the boss-cutscene scripts.

Output: game/data/fixed_rooms.json
  rooms[n]      = {w, h, flags, tiles: [action ids, row-major]}         (fixedmap.inc, sub_80511F0 RLE)
  entities[a]   = {item, qty, sp, behavior, trap, trap_visible, room, secondary}   action id a = 16 + index
  levels[dungeon_key][floor] = {species_key: level}   (0-probability spawn entries Red uses for bosses)
  dialogue[name] = [{type, emo, place, speaker, allow, text}, ...]   (dungeon_boss_dialogue.c)
  cutscenes[...]  see gen_cutscenes() below
Personal use only (data derived from the user's own ROM / the pret decomp).
"""
import json, os, re, subprocess, sys, tempfile
sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
import redsrc  # noqa: E402

DEC = common.PMDRED
GAME = common.GAME
OUT = GAME + "/data/fixed_rooms.json"
CFLAGS = ["-w", "-O0", "-iquote", DEC + "/include", "-iquote", DEC, "-iquote", DEC + "/src", "-D_(x)=x", "-D__(x)=x"]

RED_MON = redsrc.red_mon_map()   # same as data/ground/extra.json "red_mon" (made later by tools/ground)
items = json.load(open(GAME + "/data/items.json"))
RED_ITEM = {}
for k, v in items.items():
    if "red_id" in v:
        RED_ITEM.setdefault(int(v["red_id"]), k)
TRAPS = ["trip", "mud", "sticky", "grimy", "summon", "pitfall", "warp", "gust", "spin", "slumber", "slow", "seal",
         "poison", "selfdestruct", "explosion", "ppzero", "chestnut", "wonder", "pokemon", "spiked"]


def enum_values(path, start_name=None):
    """Parse a C enum file into name -> value (sequential, honouring explicit = values)."""
    txt = re.sub(r"//[^\n]*|/\*.*?\*/", "", open(path).read(), flags=re.S)
    out = {}
    for body in re.findall(r"enum\s*\w*\s*\{(.*?)\}", txt, re.S):
        v = -1
        for ent in body.split(","):
            ent = ent.strip()
            if not ent:
                continue
            if "=" in ent:
                n, e = [x.strip() for x in ent.split("=", 1)]
                try:
                    v = int(eval(e, {}, out))
                except Exception:
                    v += 1
            else:
                n = ent
                v += 1
            out[n] = v
    for m in re.finditer(r"^#define\s+(\w+)\s+(.+)$", txt, re.M):
        try:
            out[m.group(1)] = int(eval(m.group(2), {}, dict(out)))
        except Exception:
            pass
    return out


def species_key(red_id):
    if red_id in RED_MON:
        return RED_MON[red_id]
    return ""


# ------------------------------------------------------------------ C helper: entities + dialogue
def compile_dump():
    src_fixed = open(DEC + "/src/dungeon_generation_fixed.c").read()
    a = src_fixed.index("struct FixedRoomEntitiesInfo\n{")
    b = src_fixed.index("};", src_fixed.index("sFixedRoomEntities[204]")) + 2
    table = src_fixed[a:b]
    dlg_hdr = open(DEC + "/include/dungeon_boss_dialogue.h").read()
    names = re.findall(r"extern const struct DungeonDialogueStruct (\w+)(\[\])?;", dlg_hdr)
    c = ['#include "global.h"', '#include "constants/monster.h"', '#include "constants/item.h"',
         '#include "constants/trap.h"', '#include "structs/dungeon_entity.h"', '#include "dungeon_message.h"',
         '#include "dungeon_boss_dialogue.h"', '#include <stdio.h>', table,
         'static void js(const char *s){putchar(34);for(;s && *s;s++){unsigned char ch=*s;'
         'if(ch==34||ch==92){putchar(92);putchar(ch);}else if(ch==10)fputs("\\\\n",stdout);'
         'else if(ch<32)printf("\\\\u%04x",ch);else putchar(ch);}putchar(34);}',
         'static void dlg(const char *name, const struct DungeonDialogueStruct *d, int arr){',
         ' printf("%s\\"%s\\":[", name[0]==1?"":",", name+1);',
         ' for(int i=0;;i++){ if(i) putchar(44);',
         '  printf("{\\"type\\":%d,\\"emo\\":%d,\\"place\\":%d,\\"speaker\\":%d,\\"allow\\":%d,\\"text\\":", d[i].type, d[i].spriteId, d[i].spritePlacementId, d[i].speciesId, d[i].allowType);',
         '  js((const char*)d[i].str); putchar(125);',
         '  if(!arr || d[i].allowType==DIALOGUE_ALLOW_ALL) break; }',
         ' putchar(93);}',
         'int main(){ printf("{\\"entities\\":[");',
         ' for(int i=0;i<204;i++){ const struct FixedRoomEntitiesInfo *e=&sFixedRoomEntities[i];',
         '  printf("%s[%d,%d,%u,%d,%d,%d,%d,%d,%d]", i?",":"", e->itemId, e->itemQuantity, e->unk4, e->speciesId, e->monsterBehavior, e->trapId, e->roomId, e->trapVisible, e->setTerrainToSecondary);}',
         ' printf("],\\"dialogue\\":{");']
    first = True
    for n, arr in names:
        c.append(' dlg("%s%s", %s%s, %d);' % ("\\x01" if first else "\\x02", n, "" if arr else "&", n, 1 if arr else 0))
        first = False
    c.append(' printf("}}"); return 0; }')
    with tempfile.TemporaryDirectory() as td:
        cf = os.path.join(td, "dump.c")
        open(cf, "w").write("\n".join(c))
        objs = []
        for s, o in [(cf, td + "/dump.o"), (DEC + "/src/dungeon_boss_dialogue.c", td + "/dlg.o")]:
            r = subprocess.run(["gcc", "-c"] + CFLAGS + [s, "-o", o], capture_output=True, text=True)
            if r.returncode != 0:
                print(r.stderr[:3000])
                sys.exit(1)
            objs.append(o)
        r = subprocess.run(["gcc"] + objs + ["-o", td + "/dump"], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stderr[:3000])
            sys.exit(1)
        raw = subprocess.run([td + "/dump"], capture_output=True).stdout
    txt = raw.decode("utf-8", errors="replace")
    return json.loads(txt)


# ------------------------------------------------------------------ fixedmap.inc
def parse_fixedmap():
    labels = {}
    order = []
    cur = None
    for line in open(DEC + "/data/dungeon/fixedmap.inc"):
        line = line.strip()
        m = re.match(r"^(\w+):$", line)
        if m:
            cur = m.group(1)
            labels[cur] = []
            order.append(cur)
            continue
        if cur is None:
            continue
        if line.startswith(".byte"):
            labels[cur] += [int(x, 0) for x in line[5:].split(",")]
        elif line.startswith(".4byte"):
            labels[cur].append(("ptr", line.split()[1]))
    table = [x[1] for x in labels["gUnknown_84A03BC"]]
    rooms = []
    for name in table:
        data = labels[name]
        w, h, flags = data[0], data[1], data[2]
        stream = data[3:]
        # sub_80511F0 RLE: byte 14 = literal next byte; else high nibble value, low nibble = extra repeats
        tiles = []
        pos = 0
        rep = 0
        val = 0
        for _ in range(w * h):
            if rep:
                rep -= 1
            else:
                if pos >= len(stream):
                    val = 0
                else:
                    val = stream[pos]
                    pos += 1
                    if val == 14:
                        val = stream[pos]
                        pos += 1
                    else:
                        rep = val & 0xF
                        val = (val & 0xF0) >> 4
            tiles.append(val)
        rooms.append({"w": w, "h": h, "flags": flags, "tiles": tiles, "label": name})
    return rooms


# ------------------------------------------------------------------ boss levels (0-probability spawn entries)
def snake(n):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", n).lower()
    return s


def boss_levels(mon_enum):
    dd = json.load(open(GAME + "/data/dungeons.json"))["dungeons"]
    keys = list(dd.keys())
    out = {}
    for d in sorted(os.listdir(DEC + "/data/dungeon")):
        p = os.path.join(DEC, "data/dungeon", d)
        if not os.path.isdir(p) or not os.path.exists(p + "/pokemon_found.json"):
            continue
        k = snake(d)
        if k not in dd:
            alt = {"mt_freeze_peak_alt": "mt_freeze_peak_alt"}
            k = alt.get(k, k)
            if k not in dd:
                continue
        fid = json.load(open(p + "/floor_id.json"))["tables"]
        pk = json.load(open(p + "/pokemon_found.json"))["tables"]
        lv = {}
        base = min(int(t["Pokemon"]) for t in fid)
        for fi, t in enumerate(fid):
            pi = int(t["Pokemon"]) - base
            if pi >= len(pk):
                continue
            m = {}
            for e in pk[pi]["pokemon"]:
                rid = mon_enum.get(e["species"], -1)
                sk = species_key(rid)
                if sk:
                    m[sk] = int(e["level"])
            lv[str(fi)] = m
        out[k] = lv
    return out


# ------------------------------------------------------------------ cutscene scripts (C -> step trees)
def strip_comments(s):
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", s, flags=re.S)


def functions_of(src):
    """name -> body text for every top-level function in a C file."""
    out = {}
    i = 0
    for m in re.finditer(r"^(?:static\s+)?(?:void|bool8|bool32|s32|u32|u8)\s+(\w+)\s*\(([^)]*)\)\s*\{", src, re.M):
        name = m.group(1)
        start = m.end()
        depth = 1
        j = start
        while depth and j < len(src):
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
            j += 1
        out[name] = (m.group(2), src[start:j - 1])
    return out


ENT_RE = r"(\w+)"


class CS:
    def __init__(self, funcs, consts):
        self.funcs = funcs
        self.consts = consts
        self.vars = {}
        self.arrays = {}
        self.ptrs = {}

    def who(self, expr):
        expr = expr.strip().lstrip("&")
        e = self.vars.get(expr, expr)
        return e

    def num(self, e):
        e = e.strip()
        try:
            return int(eval(e, {}, self.consts))
        except Exception:
            return e

    def cond(self, c):
        c = c.strip()
        while c.startswith("(") and c.endswith(")") and self._balanced(c[1:-1]):
            c = c[1:-1].strip()
        if c.startswith("!"):
            return ["not", self.cond(c[1:])]
        for op in ("||", "&&"):
            parts = self._split_top(c, op)
            if len(parts) > 1:
                return ["or" if op == "||" else "and"] + [self.cond(p) for p in parts]
        m = re.match(r"(\w+)\((.*)\)$", c)
        if m:
            f, a = m.group(1), m.group(2).strip()
            if f in ("HasRecruitedMon",):
                return ["recruited", a]
            if f == "sub_8086AE4":
                return ["recruited_or_story", a]
            if f in ("GetCutsceneFlag",):
                return ["flag", a]
            if f in ("ItemInInventoryOrHeld",):
                return ["item", a]
            if f == "sub_8097318":
                return ["misc_flag", a]
        m = re.match(r"(\w+)\s*(==|>=|<=|!=|<|>)\s*(\w+)$", c)
        if m and m.group(1) in ("menuChoice", "wishChoice"):
            return ["choice", m.group(1), m.group(2), self.num(m.group(3))]
        if m and m.group(1) == "cutscene":
            return ["cutscene", m.group(2), m.group(3)]
        if m and m.group(1) == "monsterBehavior":
            return ["behavior", m.group(2), m.group(3)]
        if c == "transformedIntoFriend":
            return ["joined"]
        if c == "stillAlive":
            return ["others_alive"]
        return ["unknown", c]

    @staticmethod
    def _balanced(s):
        d = 0
        for ch in s:
            d += ch == "("
            d -= ch == ")"
            if d < 0:
                return False
        return d == 0

    @staticmethod
    def _split_top(s, op):
        parts, d, cur, i = [], 0, "", 0
        while i < len(s):
            if s[i] == "(":
                d += 1
            elif s[i] == ")":
                d -= 1
            if d == 0 and s.startswith(op, i):
                parts.append(cur)
                cur = ""
                i += len(op)
                continue
            cur += s[i]
            i += 1
        parts.append(cur)
        return [p for p in parts if p.strip()]

    # -------------------------------------------------------------- statement parsing
    def block(self, body, depth=0):
        toks = self.statements(body)
        return self.stmts(toks, depth)

    def statements(self, body):
        """Split a C body into top-level statements / compound statements."""
        out = []
        i = 0
        n = len(body)
        while i < n:
            while i < n and body[i] in " \t\r\n;":
                i += 1
            if i >= n:
                break
            m = re.match(r"(if|else\s+if|else|for|while|do|switch)\b", body[i:])
            if m:
                kw = re.sub(r"\s+", " ", m.group(1))
                j = i + m.end()
                cond = None
                if kw in ("if", "else if", "for", "while", "switch"):
                    while body[j] in " \t\r\n":
                        j += 1
                    k = self._match(body, j, "(", ")")
                    cond = body[j + 1:k]
                    j = k + 1
                while j < n and body[j] in " \t\r\n":
                    j += 1
                if j < n and body[j] == "{":
                    k = self._match(body, j, "{", "}")
                    inner = body[j + 1:k]
                    j = k + 1
                else:
                    k = body.find(";", j)
                    inner = body[j:k + 1]
                    j = k + 1
                if kw == "do":
                    # do { } while (...);
                    k = body.find(";", j)
                    j = k + 1
                out.append((kw, cond, inner))
                i = j
                continue
            if body[i] == "{":
                k = self._match(body, i, "{", "}")
                out.append(("block", None, body[i + 1:k]))
                i = k + 1
                continue
            k = i
            d = 0
            while k < n:
                if body[k] in "({":
                    d += 1
                elif body[k] in ")}":
                    d -= 1
                elif body[k] == ";" and d == 0:
                    break
                k += 1
            out.append(("stmt", None, body[i:k].strip()))
            i = k + 1
        return out

    @staticmethod
    def _match(s, i, a, b):
        d = 0
        for k in range(i, len(s)):
            if s[k] == a:
                d += 1
            elif s[k] == b:
                d -= 1
                if d == 0:
                    return k
        return len(s) - 1

    def stmts(self, toks, depth):
        steps = []
        i = 0
        while i < len(toks):
            kw, cond, inner = toks[i]
            if kw == "if":
                node = ["if", self.cond(cond), self.block(inner, depth), []]
                steps.append(node)
                cur = node
                while i + 1 < len(toks) and toks[i + 1][0] in ("else if", "else"):
                    i += 1
                    k2, c2, in2 = toks[i]
                    if k2 == "else if":
                        sub = ["if", self.cond(c2), self.block(in2, depth), []]
                        cur[3] = [sub]
                        cur = sub
                    else:
                        cur[3] = self.block(in2, depth)
                if not node[2] and not node[3]:
                    steps.pop()
            elif kw in ("for", "while", "do"):
                inner_steps = self.block(inner, depth)
                inner_steps = [s for s in inner_steps if s[0] in ("say", "ask", "bgm", "bgm_stop", "show", "hide")]
                if kw == "do" and "DisplayDungeonMenuMessage" in inner:
                    steps += self.stmt_steps(inner.strip().rstrip(";"), depth)
                else:
                    steps += inner_steps
                    if "SetDungeonBGColorRGB" in inner or "ScreenFlash" in inner:
                        steps.append(["flash"])
            elif kw == "block":
                steps += self.block(inner, depth)
            elif kw == "switch":
                pass
            else:
                steps += self.stmt_steps(inner, depth)
            i += 1
        return steps

    def stmt_steps(self, s, depth):
        s = s.strip()
        if not s:
            return []
        m = re.match(r"(?:\w+[\s*]+)?(\w+)\s*=\s*(GetEntityFromMonsterBehavior|CutsceneGetLeader|CutsceneGetPartner|GetLeader)\((.*)\)$", s)
        if m:
            v, f, a = m.groups()
            self.vars[v] = {"CutsceneGetLeader": "leader", "GetLeader": "leader", "CutsceneGetPartner": "partner"}.get(f, a.strip())
            return []
        # sub_8085B4C walk paths: s16 arrays {dir, px/frame, frames, 0}... {.., frames=0} then x, y; pointer arrays
        m = re.match(r"s16\s+(\w+)\s*\[\s*\w*\s*\]\s*=\s*\{(.*)\}$", s, re.S)
        if m:
            vals = [self.num(x.strip()) for x in m.group(2).split(",") if x.strip()]
            self.arrays[m.group(1)] = [v if isinstance(v, int) else 0 for v in vals]
            return []
        m = re.match(r"(\w+)\s*=\s*\(struct\s+\w+\)\s*\{(.*)\}$", s, re.S)
        if m:
            vals = [self.num(x.strip()) for x in m.group(2).split(",") if x.strip()]
            self.arrays[m.group(1)] = [v if isinstance(v, int) else 0 for v in vals]
            return []
        m = re.match(r"(\w+)\s*\[\s*(\d+)\s*\]\s*=\s*&?(\w+)(?:\.unk0)?$", s)
        if m:
            self.ptrs.setdefault(m.group(1), {})[int(m.group(2))] = m.group(3)
            return []
        m = re.match(r"(\w+)\s*=\s*DisplayDungeonMenuMessage\((.*)\)$", s)
        if m:
            args = [x.strip() for x in m.group(2).split(",")]
            return [["menu", m.group(1), args[1], args[2]]]
        if re.match(r"gDungeon->unk2\s*=\s*DUNGEON_UNK2_1", s):
            return [["floor_over"]]
        if re.match(r"gDungeon->unk4\s*=\s*1$", s):
            return [["dungeon_end"]]          # Smeargle / Medicham: the rescue ends the expedition
        m = re.match(r"(\w+)\((.*)\)$", s, re.S)
        if not m:
            return []
        f, a = m.group(1), m.group(2)
        args = [x.strip() for x in self._split_top(a, ",")] if a.strip() else []
        if f == "sub_8085B4C":
            n = self.num(args[3])
            paths, ents = args[1].lstrip("&"), args[2].lstrip("&")
            out = []
            for k in range(n if isinstance(n, int) else 0):
                arr = self.arrays.get(self.ptrs.get(paths, {}).get(k, ""))
                ent = self.ptrs.get(ents, {}).get(k)
                if arr and ent:
                    out.append([self.who(ent), arr])
            return [["march", out]] if out else []
        if f == "DisplayDungeonDialogue_Async":
            return [["say", args[0].lstrip("&")]]
        if f == "sub_80866C4":
            return [["look_around", "leader"], ["say", args[0].lstrip("&")], ["floor_over"]]
        if f == "DungeonWaitFrames_Async":
            v = self.num(args[0])
            return [["wait", v if isinstance(v, int) else 10]]
        if f == "DungeonStartNewBGM":
            return [["bgm", self.num(args[0])]]
        if f in ("DungeonStopBGM", "DungeonFadeOutBGM"):
            return [["bgm_stop"]]
        if f == "SetupBossFightHP":
            return [["boss_hp", self.who(args[0]), self.num(args[1]), self.num(args[2]) if len(args) > 2 else -1]]
        if f == "PlaySoundEffect":
            v = self.num(args[0])
            return [["sfx", v]] if isinstance(v, int) else []
        if f == "SpriteShockEffect":
            return [["emote", self.who(args[0]), "shock"]]
        if f == "CutsceneLookAroundEffect_Async":
            return [["look_around", self.who(args[0])]]
        if f in ("CutsceneLookDir_Async",):
            return [["face", self.who(args[0]), args[-1]]]
        if f in ("SetFacingDirection", "sub_806CE68"):
            return [["face", self.who(args[0]), args[-1]]]
        if f == "sub_8086A3C":
            return [["hide", self.who(args[0])]]
        if f == "sub_8086A54":
            return [["show", self.who(args[0])]]
        if f == "HandleFaint_Async":
            return [["remove", self.who(args[0])]]
        if f == "sub_8085930":
            return [["team_face", args[0]]]
        if f == "ShiftCameraToPosition":
            return [["camera", args[0]]]
        if f == "sub_8085860":
            return [["camera_at", args[0], args[1] if len(args) > 1 else "0"]]
        if f == "SetTempCutsceneFlag":
            return [["set_flag", args[0]]]
        if f == "UnsetCutsceneFlag":
            return [["unset_flag", args[0]]]
        if f == "LevelUpTarget":
            return []
        if f == "CopyMonsterNameToBuffer":
            mm = re.match(r"gFormatBuffer_Monsters\[(\d+)\]", args[0])
            if mm:
                return [["name", int(mm.group(1)), args[1]]]
            return []
        if f.endswith("ScreenFlash") or f.endswith("ScreenFlash1") or f.endswith("ScreenFlash2") or f.endswith("ScreenFlash3") or f in ("sub_8086738", "sub_8086764", "sub_8086794"):
            return [["flash"]]
        if f in self.funcs and depth < 8:
            params, body = self.funcs[f]
            # inline helper (bind entity params by position)
            pnames = [p.strip().split()[-1].lstrip("*") for p in params.split(",") if p.strip() and p.strip() != "void"]
            saved = dict(self.vars)
            for pn, av in zip(pnames, args):
                self.vars[pn] = self.who(av)
                if pn not in ("dialogue",):
                    self.consts.setdefault(pn, self.num(av) if isinstance(self.num(av), int) else 0)
            res = self.block(strip_comments(body), depth + 1)
            self.vars = saved
            return res
        return []


def gen_cutscenes():
    consts = {}
    for p in ["constants/cutscenes.h", "constants/bg_music.h", "constants/direction.h", "structs/dungeon_entity.h"]:
        if os.path.exists(DEC + "/include/" + p):
            consts.update(enum_values(DEC + "/include/" + p))
    for p in ["constants/bg_music.h", "constants/direction.h"]:
        for m in re.finditer(r"#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)", open(DEC + "/include/" + p).read()):
            consts[m.group(1)] = int(m.group(2), 0)
    funcs = {}
    files = sorted(f for f in os.listdir(DEC + "/src") if f.startswith("dungeon_cutscene"))
    for f in files:
        funcs.update(functions_of(strip_comments(open(DEC + "/src/" + f).read())))
    main = strip_comments(open(DEC + "/src/dungeon_cutscene.c").read())

    def dispatch(fname):
        body = funcs[fname][1]
        table = {}
        for m in re.finditer(r"((?:case \w+:\s*)+)(.*?)break;", body, re.S):
            cases = re.findall(r"case (\w+):", m.group(1))
            calls = re.findall(r"(\w+)\(", m.group(2))
            for c in cases:
                table[c] = calls
        return table

    setup = dispatch("sub_80848F0")
    prefight = dispatch("DisplayPreFightDialogue")
    faint = dispatch("HandleBossFaint_Async")
    lookup = []
    m = re.search(r"sFixedRoomCutsceneLookup\[\] = \{(.*?)\n\};", main, re.S)
    for row in re.findall(r"\{([^{}]*)\}", m.group(1)):
        parts = [x.strip() for x in row.split(",")]
        if parts[0] == "FIXED_ROOM_NONE":
            break
        lookup.append(parts)
    fixed_enum = enum_values(DEC + "/include/constants/fixed_rooms.h")
    out = {"lookup": [], "scenes": {}}
    for p in lookup:
        fr = fixed_enum.get(p[0], fixed_enum.get("FIXED_ROOM_" + p[0], 0)) if not p[0].isdigit() else int(p[0])
        if p[0] == "FIRST_DOJO_MAZE_BOSS_ROOM":
            fr = fixed_enum["FIXED_ROOM_NORMAL_MAZE_BOSS"]
        out["lookup"].append({"room": fr, "c1": p[1], "f2": p[2], "c2": p[3], "f3": p[4], "c3": p[5]})
    names = set()
    for p in lookup:
        names |= {p[1], p[3], p[5]}
    for cs in sorted(names):
        sc = {}
        for kind, tab in (("setup", setup), ("prefight", prefight), ("faint", faint)):
            steps = []
            for call in tab.get(cs, []):
                if call in funcs:
                    t = CS(funcs, dict(consts))
                    t.vars = {}
                    t.consts["cutscene"] = consts.get(cs, 0)
                    params = funcs[call][0]
                    # faint handlers: (monsterBehavior, cutscene) style parameters stay symbolic
                    steps += t.block(funcs[call][1])
            sc[kind] = steps
        out["scenes"][cs] = sc
    return out


def main():
    mon_enum = enum_values(DEC + "/include/constants/monster.h")
    beh = enum_values(DEC + "/include/structs/dungeon_entity.h")
    beh_names = {v: k for k, v in beh.items() if k.startswith("BEHAVIOR_")}
    d = compile_dump()
    rooms = parse_fixedmap()
    ents = []
    for e in d["entities"]:
        item, qty, unk4, sp, bh, trap, room, tvis, sec = e
        ents.append({"item": RED_ITEM.get(item, "") if item else "", "qty": qty, "slot": unk4 if not item else 0,
                     "sp": species_key(sp) if sp and sp < 1000 else ("decoy" if sp else ""), "red_sp": sp,
                     "behavior": beh_names.get(bh, str(bh)) if sp else "",
                     "trap": TRAPS[trap] if trap < len(TRAPS) else "", "trap_visible": bool(tvis),
                     "room": room, "secondary": bool(sec)})
    dialogue = d["dialogue"]
    mon_enum["MONSTER_MAX"] = mon_enum["MONSTER_RAYQUAZA_CUTSCENE"] + 1
    for k, lst in dialogue.items():
        for x in lst:
            sp = x["speaker"]
            x["speaker"] = {mon_enum["MONSTER_MAX"] + 1: "leader", mon_enum["MONSTER_MAX"] + 2: "partner",
                            mon_enum["MONSTER_MAX"] + 3: ""}.get(sp, species_key(sp) if sp else "")
    # name constants for cutscene NAME buffers
    out = {"rooms": rooms, "entities": ents, "levels": boss_levels(mon_enum), "dialogue": dialogue,
           "cutscenes": gen_cutscenes(),
           "monsters": {k: species_key(v) for k, v in mon_enum.items() if k.startswith("MONSTER_") and species_key(v)},
           "items": {}}
    item_enum = enum_values(DEC + "/include/constants/item.h")
    out["items"] = {k: RED_ITEM[v] for k, v in item_enum.items() if k.startswith("ITEM_") and v in RED_ITEM}
    json.dump(out, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
    print("rooms", len(rooms), "entities", len(ents), "dialogue", len(dialogue), "scenes", len(out["cutscenes"]["scenes"]),
          "bytes", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
