#!/usr/bin/env python3
"""Dump PMD Red's ground scripts (cutscenes, NPCs, town logic) from the pret/pmd-red decomp to JSON.

The decomp's data files are C initializers, so instead of parsing C we compile them on the host together
with a small dumper and let the compiler resolve every macro, enum and pointer:
  * one wrapper TU per ground_data_*.c / ground_event_data.c registers each ScriptCommand / GroundLink array
    with its element count (static arrays are only visible inside their own TU),
  * dump.c walks gMapScriptTable (map id -> GroundScriptHeader), gFunctionScriptTable (shared scripts by
    ScriptID), gScriptVarInfo, gGroundMapConversionTable, gMapFilesTable and prints JSON.
Enum names (maps, script ids, vars...) are parsed from the headers here.

Output: game/data/ground/scripts.json (all command arrays), maps.json, common.json (functions, vars,
enums, map conversion, map files).
"""
import glob, json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common as CM  # noqa: E402

DEC = CM.PMDRED
OUT = os.path.join(CM.DATA, "ground")
WORK = os.path.join(CM.TMP, "gsdump", "w")      # reg.h goes in its parent
os.makedirs(WORK, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

CFLAGS = ["-w", "-O0", "-iquote", DEC + "/include", "-iquote", DEC, "-iquote", DEC + "/src", "-D_(x)=x", "-D__(x)=x"]

# ---------------------------------------------------------------- wrapper TUs
srcs = sorted(glob.glob(DEC + "/src/ground_data_*.c")) + [DEC + "/src/ground_event_data.c"]
reg_names = []
for s in srcs:
    base = os.path.basename(s)[:-2]
    hdr = DEC + "/src/data/ground/" + base + ".h"
    txt = open(hdr, encoding="utf-8", errors="replace").read()
    cmds = re.findall(r"static const struct ScriptCommand\s+(\w+)\s*\[\s*\]", txt)
    links = re.findall(r"static const struct GroundLink\s+(\w+)\s*\[\s*\]", txt)
    w = ['#include "%s"' % s, '#include "../reg.h"']
    w.append("const struct ArrReg reg_%s[] = {" % base)
    for n in cmds:
        w.append('  { %s, sizeof(%s)/sizeof(%s[0]), "%s", 0 },' % (n, n, n, n))
    for n in links:
        w.append('  { %s, sizeof(%s)/sizeof(%s[0]), "%s", 1 },' % (n, n, n, n))
    w.append("  { 0, 0, 0, 0 } };")
    open(os.path.join(WORK, "w_" + base + ".c"), "w").write("\n".join(w) + "\n")
    reg_names.append("reg_" + base)

open(os.path.join(os.path.dirname(WORK), "reg.h"), "w").write(
    "#ifndef REG_H\n#define REG_H\nstruct ArrReg { const void *p; int n; const char *name; int kind; };\n#endif\n")

DUMP = r'''
#include "global.h"
#include "globaldata.h"
#include "structs/str_ground_script.h"
#include "map_script_table.h"
#include "script_vars_info.h"
#include "ground_map_conversion_table.h"
#include "map_files_table.h"
#include "../reg.h"
#include <stdio.h>
%(externs)s
static const struct ArrReg *const regs[] = { %(regs)s };

static void str(FILE *f, const char *s) {
    if (!s) { fputs("null", f); return; }
    fputc('"', f);
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (*p == '"' || *p == '\\') { fputc('\\', f); fputc(*p, f); }
        else if (*p == '\n') fputs("\\n", f);
        else if (*p < 0x20) fprintf(f, "\\u%%04x", *p);
        else fputc(*p, f);
    }
    fputc('"', f);
}
static const char *arrname(const void *p) {
    if (!p) return NULL;
    for (unsigned r = 0; r < sizeof(regs)/sizeof(regs[0]); r++)
        for (const struct ArrReg *a = regs[r]; a->p; a++)
            if (a->p == p) return a->name;
    for (unsigned r = 0; r < sizeof(regs)/sizeof(regs[0]); r++)          /* pointer into the middle of an array */
        for (const struct ArrReg *a = regs[r]; a->p; a++)
            if (a->kind == 0 && (const ScriptCommand *)p > (const ScriptCommand *)a->p &&
                (const ScriptCommand *)p < (const ScriptCommand *)a->p + a->n) {
                static char buf[64][128]; static int k; k = (k + 1) & 63;
                snprintf(buf[k], 128, "%%s+%%d", a->name, (int)((const ScriptCommand *)p - (const ScriptCommand *)a->p));
                return buf[k];
            }
    return "?unknown";
}
static void sref(FILE *f, const ScriptRef *r) {
    if (!r) { fputs("null", f); return; }
    fprintf(f, "{\"id\":%%d,\"type\":%%d,\"script\":", r->id, r->type); str(f, arrname(r->script)); fputc('}', f);
}
static void cpos(FILE *f, CompactPos p) { fprintf(f, "[%%d,%%d,%%d,%%d]", p.xTiles, p.yTiles, p.xFlags, p.yFlags); }
static int linkcount(const struct GroundLink *l) {
    for (unsigned r = 0; r < sizeof(regs)/sizeof(regs[0]); r++)
        for (const struct ArrReg *a = regs[r]; a->p; a++) if (a->p == l) return a->n;
    return 0;
}

int main(void) {
    FILE *f = fopen("scripts.json", "w");
    fputc('{', f);
    int first = 1;
    for (unsigned r = 0; r < sizeof(regs)/sizeof(regs[0]); r++)
        for (const struct ArrReg *a = regs[r]; a->p; a++) {
            if (a->kind) continue;
            if (!first) fputs(",\n", f); first = 0;
            str(f, a->name); fputs(":[", f);
            const ScriptCommand *c = a->p;
            for (int i = 0; i < a->n; i++) {
                if (i) fputc(',', f);
                fprintf(f, "[%%d,%%d,%%d,%%d,%%d,", c[i].op, c[i].argByte, c[i].argShort, c[i].arg1, c[i].arg2);
                str(f, (const char *)c[i].argPtr); fputc(']', f);
            }
            fputc(']', f);
        }
    fputs("}\n", f); fclose(f);

    f = fopen("maps.json", "w");
    fputc('[', f);
    for (int m = 0; m < MAP_COUNT; m++) {
        const GroundScriptHeader *h = gMapScriptTable[m];
        if (m) fputs(",\n", f);
        if (!h) { fputs("null", f); continue; }
        fputs("{\"groups\":[", f);
        for (u32 g = 0; g < h->nGroups; g++) {
            if (g) fputc(',', f);
            fputc('[', f);
            for (u32 s = 0; s < h->groups[g].nSectors; s++) {
                const struct GroundScriptSector *sec = &h->groups[g].sectors[s];
                if (s) fputc(',', f);
                fputs("{\"lives\":[", f);
                for (u32 i = 0; i < sec->nLives; i++) {
                    const GroundLivesData *l = &sec->lives[i];
                    if (i) fputc(',', f);
                    fprintf(f, "{\"kind\":%%d,\"u1\":%%d,\"w\":%%d,\"h\":%%d,\"pos\":", l->kind, l->unk1, l->width, l->height); cpos(f, l->pos);
                    fputs(",\"scripts\":[", f);
                    for (int k = 0; k < 4; k++) { if (k) fputc(',', f); str(f, arrname(l->scripts[k])); }
                    fputs("]}", f);
                }
                fputs("],\"objects\":[", f);
                for (u32 i = 0; i < sec->nObjects; i++) {
                    const GroundObjectData *l = &sec->objects[i];
                    if (i) fputc(',', f);
                    fprintf(f, "{\"kind\":%%d,\"u1\":%%d,\"w\":%%d,\"h\":%%d,\"pos\":", l->kind, l->unk1, l->width, l->height); cpos(f, l->pos);
                    fputs(",\"scripts\":[", f);
                    for (int k = 0; k < 4; k++) { if (k) fputc(',', f); str(f, arrname(l->scripts[k])); }
                    fputs("]}", f);
                }
                fputs("],\"effects\":[", f);
                for (u32 i = 0; i < sec->nEffects; i++) {
                    const GroundEffectData *l = &sec->effects[i];
                    if (i) fputc(',', f);
                    fprintf(f, "{\"kind\":%%d,\"u1\":%%d,\"w\":%%d,\"h\":%%d,\"pos\":", l->kind, l->unk1, l->width, l->height); cpos(f, l->pos);
                    fputs(",\"script\":", f); str(f, arrname(l->script)); fputc('}', f);
                }
                fputs("],\"events\":[", f);
                for (u32 i = 0; i < sec->nEvents; i++) {
                    const GroundEventData *l = &sec->events[i];
                    if (i) fputc(',', f);
                    fprintf(f, "{\"kind\":%%d,\"u1\":%%d,\"w\":%%d,\"h\":%%d,\"pos\":", l->kind, l->unk1, l->width, l->height); cpos(f, l->pos);
                    fputs(",\"ref\":", f); sref(f, l->script); fputc('}', f);
                }
                fputs("],\"station\":", f);
                if (sec->hasStation && sec->station) sref(f, *sec->station); else fputs("null", f);
                fputc('}', f);
            }
            fputc(']', f);
        }
        fputs("],\"links\":[", f);
        int nl = h->links ? linkcount(h->links) : 0;
        for (int i = 0; i < nl; i++) {
            const struct GroundLink *l = &h->links[i];
            if (i) fputc(',', f);
            fputs("{\"pos\":", f); cpos(f, l->pos);
            fprintf(f, ",\"w\":%%d,\"h\":%%d,\"ret\":%%d,\"u7\":%%d}", l->width, l->height, l->ret, l->unk7);
        }
        fputs("]}", f);
    }
    fputs("]\n", f); fclose(f);

    f = fopen("common.json", "w");
    fputs("{\"functions\":[", f);
    for (int i = 0; i < NUM_SCRIPT_IDS; i++) {
        const ScriptRef *r = &gFunctionScriptTable[i];
        if (i) fputs(",\n", f);
        fprintf(f, "{\"id\":%%d,\"type\":%%d,\"name\":", r->id, r->type); str(f, (const char *)r->name);
        fputs(",\"script\":", f); str(f, arrname(r->script)); fputc('}', f);
    }
    fputs("],\n\"vars\":[", f);
    for (int i = 0; i < SCRIPT_VARS_COUNT; i++) {
        const struct ScriptVarInfo *v = &gScriptVarInfo[i];
        if (i) fputs(",\n", f);
        fprintf(f, "{\"type\":%%d,\"u2\":%%d,\"off\":%%d,\"bit\":%%d,\"len\":%%d,\"def\":%%d,\"name\":", v->type, v->unk2, v->bufOffset, v->bitOffset, v->arrayLen, v->defaultValue);
        str(f, v->name); fputc('}', f);
    }
    fputs("],\n\"map_conv\":[", f);
    for (int i = 0; i < MAP_COUNT; i++) {
        const GroundConversionStruct *c = &gGroundMapConversionTable[i];
        if (i) fputs(",\n", f);
        fprintf(f, "{\"u0\":%%d,\"place\":%%d,\"file\":%%d,\"u6\":%%d}", c->unk0, c->groundPlaceId, c->mapFileTableId, c->unk6);
    }
    fputs("],\n\"map_files\":[", f);
    for (int i = 0; i < MAP_FILE_ID_COUNT; i++) {
        const struct MapFilesStruct *m = &gMapFilesTable[i];
        if (i) fputs(",\n", f);
        fputs("{\"bpl\":", f); str(f, (const char *)m->bplFileName);
        fputs(",\"bpc\":", f); str(f, (const char *)m->bpcFileName);
        fputs(",\"bma\":", f); str(f, (const char *)m->bmaFileName);
        fputs(",\"bpa\":[", f);
        for (int k = 0; k < 4; k++) { if (k) fputc(',', f); str(f, (const char *)m->bpaFileNames[k]); }
        fputs("]}", f);
    }
    fputs("]}\n", f); fclose(f);
    return 0;
}
'''
externs = "\n".join("extern const struct ArrReg %s[];" % n for n in reg_names)
open(os.path.join(WORK, "dump.c"), "w").write(DUMP % {"externs": externs, "regs": ", ".join(reg_names)})

objs = []
units = [os.path.join(WORK, f) for f in sorted(os.listdir(WORK)) if f.startswith("w_") and f.endswith(".c")]
units += [os.path.join(WORK, "dump.c")] + [DEC + "/src/" + n for n in
          ["map_script_table.c", "script_vars_info.c", "ground_map_conversion_table.c", "map_files_table.c"]]
for u in units:
    o = os.path.join(WORK, os.path.basename(u)[:-2] + ".o")
    r = subprocess.run(["gcc", "-c"] + CFLAGS + ["-I", os.path.dirname(WORK), u, "-o", o], capture_output=True, text=True)
    if r.returncode:
        sys.exit("compile failed %s\n%s" % (u, r.stderr[:3000]))
    objs.append(o)
exe = os.path.join(WORK, "dump")
r = subprocess.run(["gcc"] + objs + ["-o", exe], capture_output=True, text=True)
if r.returncode:
    sys.exit("link failed\n" + r.stderr[:3000])
subprocess.run([exe], cwd=WORK, check=True)


# ---------------------------------------------------------------- enums
def parse_enum(path, enum_name=None, first_enum=False):
    """Names in order of value for `enum NAME {...}` (or the first enum in the file)."""
    t = open(path, encoding="utf-8", errors="replace").read()
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    if enum_name:
        m = re.search(r"enum\s+%s\s*\{(.*?)\}" % enum_name, t, re.S)
    else:
        m = re.search(r"enum\s*\w*\s*\{(.*?)\}", t, re.S)
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
                v = v + 1
        else:
            n = item
            v += 1
        env[n] = v
        out[n] = v
    return out


def ld(name):
    raw = open(os.path.join(WORK, name), "rb").read()
    return json.loads(raw.decode("utf-8", errors="replace"))


scripts = ld("scripts.json")
maps = ld("maps.json")
common = ld("common.json")
enums = {
    "maps": parse_enum(DEC + "/include/constants/ground_map.h"),
    "script_ids": parse_enum(DEC + "/include/constants/script_id.h", "ScriptID"),
    "vars": parse_enum(DEC + "/include/constants/event_flag.h"),
    "map_files": parse_enum(DEC + "/include/map_files_table.h"),
    "script_dungeons": parse_enum(DEC + "/include/constants/script_dungeon_id.h"),
}
common["enums"] = {k: {str(v): n for n, v in e.items()} for k, e in enums.items()}
for name, data in [("scripts.json", scripts), ("maps.json", maps), ("common.json", common)]:
    json.dump(data, open(os.path.join(OUT, name), "w"), separators=(",", ":"), ensure_ascii=False)
n_cmd = sum(len(v) for v in scripts.values())
unknown = sum(1 for m in maps if m for g in m["groups"] for s in g for l in s["lives"] for x in l["scripts"] if x and x.startswith("?"))
print("scripts", len(scripts), "commands", n_cmd, "maps", sum(1 for m in maps if m), "/", len(maps),
      "functions", len(common["functions"]), "vars", len(common["vars"]), "unresolved", unknown)
