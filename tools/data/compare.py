#!/usr/bin/env python3
"""Compare the stage-1 data outputs with a reference game folder (set REF_GAME to its path,
or REF_GAME=...). Files that stage 2 changes are compared with snapshots taken before stage 2 when they exist
(REF_STAGE1=folder with items_before_eos.json, moves_before_fix.json, species_before_megas.json, dungeons_before_spread.json).
Prints per file: identical bytes / same content / differences (paths)."""
import json
import os
import sys

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__)))]
import common  # noqa: E402

REF = os.environ.get("REF_GAME", "")
SNAP = os.environ.get("REF_STAGE1", "")
FILES = ["species.json", "growth.json", "evo.json", "types.json", "moves.json", "items.json", "dungeons.json",
         "friend_areas.json", "fixed_rooms.json", "iq.json", "quiz.json", "missions.json", "red_evo.json",
         "red_town_text.json", "menu_text.json", "kecleon_sets.json", "item_icons.json"]
STAGE1 = {"items.json": "items_before_eos.json", "moves.json": "moves_before_fix.json",
          "species.json": "species_before_megas.json", "dungeons.json": "dungeons_before_spread.json"}


def diffs(a, b, path="", out=None):
    out = [] if out is None else out
    if type(a) is not type(b) and not (isinstance(a, (int, float)) and isinstance(b, (int, float))):
        out.append((path, a, b))
    elif isinstance(a, dict):
        for k in list(a) + [k for k in b if k not in a]:
            if k not in a or k not in b:
                out.append((path + "/" + str(k), a.get(k, "<missing>"), b.get(k, "<missing>")))
            else:
                diffs(a[k], b[k], path + "/" + str(k), out)
    elif isinstance(a, list):
        if len(a) != len(b):
            out.append((path, "len %d" % len(a), "len %d" % len(b)))
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                diffs(x, y, "%s/%d" % (path, i), out)
    elif a != b:
        out.append((path, a, b))
    return out


def main():
    for f in FILES:
        mine = os.path.join(common.DATA, f)
        ref = os.path.join(SNAP, STAGE1[f]) if f in STAGE1 and os.path.exists(os.path.join(SNAP, STAGE1.get(f, ""))) else os.path.join(REF, "data", f)
        if not os.path.exists(mine) or not os.path.exists(ref):
            print("%-20s missing (%s)" % (f, mine if not os.path.exists(mine) else ref))
            continue
        if open(mine, "rb").read() == open(ref, "rb").read():
            print("%-20s identical bytes" % f)
            continue
        a, b = common.load_json(mine), common.load_json(ref)
        if f == "dungeons.json":        # stage 1 makes Red's dungeons; the snapshot also has vanilla EoS ones
            b = {**b, "dungeons": {k: v for k, v in b["dungeons"].items() if not v.get("eos")}}
            b["item_tables"] = b["item_tables"][:len(a["item_tables"])]
            b["trap_tables"] = b["trap_tables"][:len(a["trap_tables"])]
        d = diffs(a, b)
        if not d:
            print("%-20s same content (formatting differs)" % f)
            continue
        print("%-20s %d differences vs %s" % (f, len(d), os.path.basename(ref)))
        for p, x, y in d[:5]:
            print("    %s: %s | %s" % (p, json.dumps(x, ensure_ascii=False)[:80], json.dumps(y, ensure_ascii=False)[:80]))


if __name__ == "__main__":
    main()
