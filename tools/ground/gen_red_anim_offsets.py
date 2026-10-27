"""Red's ground/dungeon sprite animations that MOVE the sprite (take-offs, landings, jumps, fly-ins).

The remake draws Pokémon with SpriteCollab sheets, which have no such animations: Skarmory's "flee"
(Red animation group 14) lifts the sprite off the screen through per-frame offsets, and without them the
script just removes Skarmory mid-scene. This reads every species' animation tables from the pret/pmd-red
decompilation (src/data/ax/<name>.h, ax_anim .frames/.offset) and keeps the groups whose offsets move the
sprite by 4 px or more. The game replays those offsets (and durations) over the matching SpriteCollab pose.

Output: game/data/ground/red_anim_offsets.json
  {"<species key>": {"<group>": [[frames, dx, dy], ...] | {"<dir>": [...], ...}}}
  A list when all 8 directions share one track, else per direction.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import common  # noqa: E402

DECOMP = common.p(common.WORK, "ext", "pmd-red")
AX_DIR = os.path.join(DECOMP, "src", "data", "ax")
GAME = os.environ.get("PMD_GAME_DIR") or os.path.join(os.path.dirname(os.path.dirname(HERE)), "game")
OUT = os.path.join(GAME, "data", "ground", "red_anim_offsets.json")
MIN_MOVE = 4
FIRST_GROUP = 10                      # Hop and the event animations (GSprite.ANIM_NAMES order)

ANIM_RE = re.compile(r"static const ax_anim (\w+)\[\] = \{(.*?)\};", re.S)
FRAME_RE = re.compile(r"\.frames = (\d+),.*?\.offset = \{(-?\d+), (-?\d+)\}")
TABLE_RE = re.compile(r"static const ax_anim \*const (\w+)\[\] = \{(.*?)\};", re.S)
MAIN_RE = re.compile(r"static const ax_anim \*const \*const (\w+)\[\] = \{(.*?)\};", re.S)


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower().replace("♀", "f").replace("♂", "m"))


def species_by_name():
    sp = json.load(open(os.path.join(GAME, "data", "species.json"), encoding="utf-8"))
    out = {}
    for k, v in sp.items():
        if len(k) != 4 or not k.isdigit():
            continue
        out.setdefault(norm(str(v.get("name", ""))), k)
    return out


def parse(path):
    src = open(path, encoding="utf-8").read()
    anims = {}
    for name, body in ANIM_RE.findall(src):
        anims[name] = [[int(f), int(x), int(y)] for f, x, y in FRAME_RE.findall(body)]
    tables = {name: [t.strip() for t in body.split(",") if t.strip()] for name, body in TABLE_RE.findall(src)}
    m = MAIN_RE.search(src)
    if not m:
        return {}
    groups = [t.strip() for t in m.group(2).split(",") if t.strip()]
    out = {}
    for g, tname in enumerate(groups):
        if g < FIRST_GROUP:
            continue                  # walk / attack / hurt ...: SpriteCollab has these, with their own motion
        dirs = [anims.get(a, []) for a in tables.get(tname, [])]
        if not any(any(abs(fr[1]) >= MIN_MOVE or abs(fr[2]) >= MIN_MOVE for fr in d) for d in dirs):
            continue
        if all(d == dirs[0] for d in dirs):
            out[str(g)] = dirs[0]
        else:
            out[str(g)] = {str(i): d for i, d in enumerate(dirs)}
    return out


SPECIAL = {"nidoranf": "0029", "nidoranm": "0032", "mrmime": "0122", "farfetchd": "0083", "hooh": "0250",
           "deoxysnormal": "0386", "deoxys": "0386", "castform": "0351", "unowna": "0201"}


def main():
    names = species_by_name()
    result = {}
    missing = []
    for fn in sorted(os.listdir(AX_DIR)):
        if not fn.endswith(".h"):
            continue
        stem = norm(fn[:-2])
        key = SPECIAL.get(stem) or names.get(stem)
        if key is None:
            missing.append(fn)
            continue
        tracks = parse(os.path.join(AX_DIR, fn))
        if tracks and key not in result:
            result[key] = tracks
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(result, open(OUT, "w"), separators=(",", ":"))
    print("red_anim_offsets.json: %d species with moving animations (%d sprite files not matched: %s)"
          % (len(result), len(missing), ", ".join(missing[:12])))


if __name__ == "__main__":
    main()
