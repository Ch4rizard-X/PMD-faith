#!/usr/bin/env python3
"""Red Rescue Team's own move animations (for Red-only builds): game/assets/fx_red/fxr<id>.png + data/red_move_fx.json.

From the pret/pmd-red decompilation (common.PMDRED):
  src/effect_data.c  gUnknown_80B9CC4[448]   effect animations: animType (3 = object effect file efobNNN,
                                             4 = full-screen background effect, 1/2 = no file), effectId (file),
                                             unk8 (palette slot, 14 = the file's own), animId, unk10 (sound),
                                             unk1c (attach point on the Pokemon, -1 = none), loop
                     gUnknown_80BDBC4[move]  per move, four effect animations played in this order
                                             (code_8040094_1.c / dungeon_move_util.c):
                                               unk0  before the attack, on the user (sub_8040C4C)
                                               unk2  on the user at the attack pose's hit frame (sub_8041108)
                                               unk6  travelling from the user to the target (sub_8056564)
                                               unk4  on the target (sub_8041168)
                                             useSineWobble: the travelling effect arcs; soundEffectId (997 = none)
  src/data/effects/efobNNN.c + data/effects/efobNNN.png/.pal   the object effects (AX poses / animations), drawn by
                                             tools/ground/gen_ornaments.py's AX renderer.
Full-screen background effects (animType 4) aren't drawn yet; effects without a picture keep their sound.

json: {"fx": {"<id>": {"poses": [[sx, sy, w, h, ox, oy], ...], "anims": [[[pose, frames, dx, dy], ...] per dir],
                       "loop": bool, "sfx": n, "attach": n}},
       "moves": {"<move key>": {"pre": id, "user": id, "proj": id, "hit": id, "arc": bool, "sfx": n,
                                "anim": Red animation index of the user (98/99: spins round),
                                "speed": the travelling effect's speed in px a frame,
                                "by": {"<species key>": [anim, sfx]} per-species overrides (gUnknown_80C183C)}}}
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path[:0] = [TOOLS, os.path.join(TOOLS, "ground")]
import common  # noqa: E402
import gen_ornaments as GO  # noqa: E402

RED = common.PMDRED
OUT = os.path.join(common.ASSETS, "fx_red")
NO_SOUND = 997


def key(n):
    return re.sub(r"[^a-z0-9]", "", n.lower())


def move_table():
    src = open(os.path.join(RED, "src", "effect_data.c")).read()
    body = src[src.index("gUnknown_80BDBC4[NUM_MOVE_IDS]"):src.index("gUnknown_80C183C[")]
    out = {}
    for m in re.finditer(r"\[MOVE_(\w+)\] = \{([^}]*)\}", body):
        f = dict(re.findall(r"\.(\w+) = (-?\w+)", m.group(2)))
        num = lambda k: int(f.get(k, "0"), 0) if re.match(r"-?\d", f.get(k, "0")) else NO_SOUND
        out[m.group(1)] = {"pre": num("unk0"), "user": num("unk2"), "proj": num("unk6"), "hit": num("unk4"),
                           "arc": f.get("useSineWobble") == "TRUE", "sfx": num("soundEffectId"),
                           "anim": num("unk10"), "speed": num("unkC"), "n": num("unk1C"), "at": num("unk20")}
    # gUnknown_80C183C: per-species overrides of the attacker's animation (sub_800EA44) and sound (sub_800E790)
    tail = src[src.index("gUnknown_80C183C[4336]"):]
    tail = tail[:tail.index("};")]
    rows = []
    for m in re.finditer(r"\{\.species = MONSTER_(\w+), \.unk2 = (-?\d+), \.unk4 = (-?\d+), \.soundEffectId = (-?\w+)\}", tail):
        snd = int(m.group(4)) if re.match(r"-?\d", m.group(4)) else NO_SOUND
        rows.append((key(m.group(1)), int(m.group(2)), snd))
    for mv in out.values():
        by = {}
        for sp, an, snd in rows[mv.pop("at"):][:mv.pop("n")]:
            by[sp] = [an, snd]
        if by:
            mv["by"] = by
    return out


_cache = {}


def render_effect(eid, tab):
    """One object effect animation (all directions it has) -> (json entry) or None."""
    anim_type, file_id, palslot, anim, sfx, _, _, attach, _, loop = tab[eid]
    sound_only = {"poses": [], "anims": [], "loop": False, "sfx": sfx, "attach": attach} if sfx > 0 else None
    if anim_type == 4:
        return render_bg(eid, file_id, sfx) or sound_only
    # 1: from efob000 (the dungeon's shared effect file), 2: efob001 (the ground's), 3: its own efobNNN
    cfile = os.path.join(RED, "src", "data", "effects", "efob%03d.c" % file_id)
    png = os.path.join(RED, "data", "effects", "efob%03d.png" % file_id)
    if not (os.path.exists(cfile) and os.path.exists(png)):
        return sound_only
    if cfile not in _cache:
        _cache[cfile] = (GO.parse_raw(cfile), GO.tiles_of_png(png),
                         GO.jasc(os.path.join(RED, "data", "effects", "efob%03d.pal" % file_id)))
    (pose_list, poses, groups, anims), vram, file_pal = _cache[cfile]

    def palette(n):
        return file_pal if n == 14 else GO.mon_pal(min(n, 13))
    if anim >= len(groups):
        return sound_only
    n_dirs = 8 if len(groups) % 8 == 0 and anim + 8 <= len(groups) else 1
    seqs = []
    for d in range(n_dirs):
        g = groups[anim + d]
        seqs.append(anims.get(g[0], []) if g else [])
    used = sorted({fr[0] for sq in seqs for fr in sq if 0 <= fr[0] < len(pose_list)})
    if not used:
        return sound_only
    imgs = []
    for pi in used:
        placed = []
        for p in poses.get(pose_list[pi], []):
            w, h = GO.SIZES[(p["shape"], p["size"])]
            pal = palette(p["pal"]) if (p["unk1"] & 2) and p["pal"] != 13 else palette(palslot)
            placed.append((p, w, h, p["rx"], p["ry"], pal))
        imgs.append(GO.render_pose(placed, vram) if placed else (GO.Image.new("RGBA", (1, 1)), 0, 0))
    remap = {pi: i for i, pi in enumerate(used)}
    GO.OUT = OUT                                      # gen_ornaments.pack writes <OUT>/<name>.png
    return {"poses": GO.pack("fxr%d" % eid, imgs), "loop": bool(loop), "sfx": sfx, "attach": attach,
            "anims": [[[remap[fr[0]], fr[1], fr[2], fr[3]] for fr in sq if fr[0] in remap] for sq in seqs]}


BG_TILE0 = 0xF00 // 32       # efbg tiles go to BG VRAM at 0xF00 (effect_sub_1.c sub_800EDF0): tilemap tile 120 = file tile 0
BG_ALPHA = 10 / 16           # drawn blended over the dungeon (BLDALPHA 0x0A0A, effect_main.c sub_800DE8C)


def render_bg(eid, file_id, sfx):
    """A full-screen background effect efbgNNN (animType 4) -> 240x160 frames for FxNode's screen mode.
    Each frame: a 33x27 RLE tilemap (graphics_memory.c sub_8009A7C) over the file's tiles, palette 14,
    shown <r5[4]> frames. r5[5] != 0 starts the blend, r5[6] sets the fade (effect_main.c sub_800DE8C):
    n > 0 fades in over n frames, n < 0 fades out, 99 = full at once. Each frame's last value is that palette
    brightness (0-1); "blend" is the 10/16 + 10/16 mix with the dungeon (0 = drawn opaque, e.g. Powder Snow)."""
    cfile = os.path.join(RED, "src", "data", "effects", "efbg%03d.c" % file_id)
    base = os.path.join(RED, "data", "effects", "efbg%03d" % file_id)
    if not (os.path.exists(cfile) and os.path.exists(base + ".png")):
        return None
    src = open(cfile).read()
    heads = {m.group(1): [int(x) for x in m.group(2).split(",") if x.strip()]
             for m in re.finditer(r"const u16 (\w+)\[\] = \{([^}]*)\};", src)}
    maps = dict(re.findall(r"const u16 (\w+)_tilemap\[\] = INCBIN_U16\(\"([^\"]+)\"\)", src))
    order = re.search(r"const u16 \*const \w+\[\] = \{([^}]*)\}", src).group(1).replace(",", " ").split()
    tiles = GO.tiles_of_png(base + ".png")
    pal = GO.jasc(base + ".pal")
    import struct
    cache, imgs, frames = {}, [], []
    bright, step, blend = 0, 0, False
    blended = False
    for name in order:
        h = heads[name]
        data = open(os.path.join(RED, maps[name]), "rb").read()
        if data not in cache:
            v = struct.unpack("<%dH" % (len(data) // 2), data)
            im = GO.Image.new("RGBA", (240, 160))
            px = im.load()
            k = run = 0
            for y in range(h[3]):
                for x in range(h[2]):
                    if run == 0:
                        c = v[k]; k += 1
                        if not c & 0xF000:
                            run = c & 0x3FF; c = 0
                    else:
                        c = 0
                    if run:
                        run -= 1
                    t = (c & 0x3FF) - BG_TILE0
                    if not c or x >= 30 or y >= 20 or not (0 <= t < len(tiles)):
                        continue
                    P = pal[(c >> 12) * 16:(c >> 12) * 16 + 16]
                    for yy in range(8):
                        for xx in range(8):
                            ci = tiles[t][yy][xx]
                            if ci:
                                px[x * 8 + (7 - xx if c & 0x400 else xx), y * 8 + (7 - yy if c & 0x800 else yy)] = tuple(P[ci]) + (255,)
            cache[data] = len(imgs)
            imgs.append((im, 0, 0))
        if h[5]:
            blend, bright, step = True, 0, 0
            blended = True
        if h[6] == 99:
            bright, step = 3100, 0
        elif h[6] > 0:
            bright = step = 3100 // h[6]
        elif h[6] < 0:
            bright, step = 3100, int(3100 / h[6])
        a = min(31, bright // 100) / 31 if blend else 1.0
        frames.append([cache[data], max(1, h[4]), round(a, 3)])
        if blend:
            bright = max(0, min(3100, bright + step))
    GO.OUT = OUT
    poses = GO.pack("fxr%d" % eid, imgs)
    return {"bg": 1, "blend": BG_ALPHA if blended else 0, "sfx": sfx, "attach": -1, "loop": False, "poses": poses,
            "frames": [[p[0], p[1], p[2], p[3], 0, 0, d, a] for p, d, a in ((poses[i], d, a) for i, d, a in frames)]}


def main():
    os.makedirs(OUT, exist_ok=True)
    tab = GO.effect_table()
    moves = move_table()
    fx = {}
    for mv in moves.values():
        for ph in ("pre", "user", "proj", "hit"):
            eid = mv[ph]
            if eid and str(eid) not in fx and eid in tab:
                e = render_effect(eid, tab)
                if e:
                    fx[str(eid)] = e
    out_moves = {}
    for name, mv in moves.items():
        ph = {k: (mv[k] if str(mv[k]) in fx else 0) for k in ("pre", "user", "proj", "hit")}
        out_moves[key(name)] = dict(ph, arc=mv["arc"], sfx=mv["sfx"], anim=mv["anim"],
                                    speed={1: 2, 2: 3}.get(mv["speed"], 6))   # px a frame (dungeon_move_util.c)
        if "by" in mv:
            out_moves[key(name)]["by"] = mv["by"]
    common.save_json(os.path.join(common.DATA, "red_move_fx.json"), {"fx": fx, "moves": out_moves})
    print("red move animations: %d moves, %d effects" % (len(out_moves), len(fx)))


if __name__ == "__main__":
    main()
