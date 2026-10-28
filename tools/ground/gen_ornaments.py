#!/usr/bin/env python3
"""Ground ornament objects (Red's ornament archive) -> game/assets/ground/orn/<name>.png + ornaments.json.

Source: pmdred_full/src/data/ornament/*.h (AX poses/animations/sprite chunks, see sprite.c AddAxSprite)
plus the 4bpp sprite chunk PNGs in graphics/ornament/<Name>/ and palettes:
  - ground_sprite_data.c gGroundObjectKinds: {animCount, palette, file}; palette >= 0x100 -> ornament palette file
    gUnknown_81178F4[pal & 0xFF] (flagNNc / titleopc / titlebgc / stoneimc), < 0x100 -> monster 'palet' slot.
  - a piece whose OAM2 unk1 has bit 1 set keeps its own OAM palette number (monster palet slot), e.g. item01.
Screen position of a piece = sprite origin + frame offset + (x + 256*unk2 - 256, y + 256*unk - 512).

json per ornament: {"poses": [[sx, sy, w, h, ox, oy], ...], "anims": [[[ [pose, frames, dx, dy], ... ] per dir] per group]}
(ox, oy) = top-left of the pose image relative to the sprite origin.
"""
import json, os, re, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common as CM  # noqa: E402

RED = CM.PMDRED
OUT = os.path.join(CM.ASSETS, "ground", "orn")

KINDS = {  # file -> palette value (ground_sprite_data.c)
    **{f"flag{n:02d}p": 0x100 + n for n in range(17)},
    **{f"flag{100 + n}p": 0x111 + n for n in range(15)},
    "titleop1": 0x120, "titleop2": 0x120, "titlebg1": 0x121,
    "npc01p": 6, "npc02p": 6, "npc03p": 5, "npc04p": 6, "item01p": 0,
    "statue": 0x122,   # MONSTER_STATUE ax422 with the stoneim palette (ground_sprite_monster.c)
}
EXT_PAL = [f"flag{n:02d}" for n in range(17)] + [f"flag{100 + n}" for n in range(15)] + ["titleop", "titlebg", "stoneim"]

SIZES = {  # (shape, size) -> (w, h)
    (0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
    (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
    (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64),
}
SHAPE = {"ST_OAM_SQUARE": 0, "ST_OAM_H_RECTANGLE": 1, "ST_OAM_V_RECTANGLE": 2}


def jasc(path):
    L = open(path).read().split("\n")
    n = int(L[2])
    return [tuple(int(v) for v in L[3 + i].split()) for i in range(n)]


def mon_pal(i):
    return jasc(f"{RED}/graphics/ax/pal/{i}.pal")


def tiles_of_png(path):
    im = Image.open(path)
    w, h = im.size
    px = im.load()
    out = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            out.append([[px[tx * 8 + x, ty * 8 + y] & 15 for x in range(8)] for y in range(8)])
    return out


def parse(hfile):
    src = open(hfile).read()
    gfx = {m.group(1): m.group(2) for m in re.finditer(r'static const u8 (\w+)\[\] = INCBIN_U8\("([^"]+)\.4bpp"\)', src)}
    # sprite chunk lists
    chunks = {}
    for m in re.finditer(r"static const ax_sprite (\w+)\[\] = \{(.*?)\};", src, re.S):
        lst = []
        for e in re.finditer(r"\{(\w+|NULL), ([^}]+)\}", m.group(2)):
            a, b = e.group(1), e.group(2).strip()
            if a == "NULL":
                n = int(b)
                if n == 0:
                    break
                lst.append(("zero", n))
            else:
                lst.append(("gfx", gfx[a]))
        chunks[m.group(1)] = lst
    poses = {}
    for m in re.finditer(r"static const ax_pose (\w+)\[\] = \{(.*?)\};", src, re.S):
        pieces = []
        for e in re.finditer(r"AX_POSE(?:_FULL)?\((.*?)\),\s*$", m.group(2), re.M):
            s = e.group(1)
            nums = re.match(r"\s*(-?\d+),(?:\s*-?\d+,\s*-?\d+,)?\s*OAM1\((\d+), (\w+)\s*, (\d+)\), OAM2\((\d+), ST_OAM_SIZE_(\d), FLIP\((\d), (\d)\), (\d+), (\d+)\), OAM3\((\d+), (\d+), (\d+)\)", s)
            if not nums:
                raise SystemExit("bad pose " + s)
            g = nums.groups()
            pieces.append(dict(sprite=int(g[0]), y=int(g[1]), shape=SHAPE[g[2]], yhi=int(g[3]), x=int(g[4]), size=int(g[5]),
                               hf=int(g[6]), vf=int(g[7]), unk1=int(g[8]), xhi=int(g[9]), tile=int(g[10]), pal=int(g[12])))
        poses[m.group(1)] = pieces
    anims = {}
    for m in re.finditer(r"static const ax_anim (\w+)\[\] = \{(.*?)\};", src, re.S):
        fr = []
        for e in re.finditer(r"\.frames = (\d+), \.unkFlags = (\d+), \.poseId = (-?\d+), \.offset = \{(-?\d+), (-?\d+)\}", m.group(2)):
            if int(e.group(1)) == 0:
                break
            fr.append([int(e.group(3)), int(e.group(1)), int(e.group(4)), int(e.group(5))])
        anims[m.group(1)] = fr
    def arr(name_re):
        m = re.search(r"static const \w+ \*const (?:\*const )?" + name_re + r"\[\] = \{(.*?)\};", src, re.S)
        return re.findall(r"(\w+),", m.group(1))
    pose_list = arr(r"sAxPoses\w+")
    sprite_list = arr(r"sAxSprites\w+")
    tables = arr(r"sAxAnimations\w+")
    groups = []
    for t in tables:
        groups.append(arr(t))
    return pose_list, poses, sprite_list, chunks, groups, anims


def build(name, hfile):
    pose_list, poses, sprite_list, chunks, groups, anims = parse(hfile)
    palval = KINDS[name]
    base_pal = jasc(f"{RED}/graphics/ornament/pal/{EXT_PAL[palval & 0xFF]}.pal") if palval >= 0x100 else mon_pal(palval)
    tile_cache = {}
    def chunk_tiles(ch):
        out = []
        for kind, v in chunks[ch]:
            if kind == "zero":
                out += [[[0] * 8 for _ in range(8)] for _ in range(v // 32)]
            else:
                if v not in tile_cache:
                    tile_cache[v] = tiles_of_png(f"{RED}/{v}.png")
                out += tile_cache[v]
        return out
    imgs = []
    for pn in pose_list:
        vram = []
        placed = []
        for p in poses[pn]:
            if p["sprite"] >= 0:
                vram += chunk_tiles(sprite_list[p["sprite"]])
            w, h = SIZES[(p["shape"], p["size"])]
            rx = p["x"] + 256 * p["xhi"] - 256
            ry = p["y"] + 256 * p["yhi"] - 512
            pal = mon_pal(p["pal"]) if (p["unk1"] & 2) and p["pal"] != 13 else base_pal
            placed.append((p, w, h, rx, ry, pal))
        if not placed:
            imgs.append((Image.new("RGBA", (1, 1)), 0, 0))
            continue
        x0 = min(q[3] for q in placed); y0 = min(q[4] for q in placed)
        x1 = max(q[3] + q[1] for q in placed); y1 = max(q[4] + q[2] for q in placed)
        im = Image.new("RGBA", (x1 - x0, y1 - y0))
        px = im.load()
        # GBA draws earlier OAM entries on top: paint in reverse
        for p, w, h, rx, ry, pal in reversed(placed):
            tw = w // 8
            for ty in range(h // 8):
                for tx in range(tw):
                    ti = p["tile"] + ty * tw + tx
                    if ti >= len(vram):
                        continue
                    t = vram[ti]
                    for yy in range(8):
                        for xx in range(8):
                            c = t[yy][xx]
                            if c == 0:
                                continue
                            dx = tx * 8 + xx; dy = ty * 8 + yy
                            if p["hf"]: dx = w - 1 - dx
                            if p["vf"]: dy = h - 1 - dy
                            r, g, b = pal[c]
                            px[rx - x0 + dx, ry - y0 + dy] = (r, g, b, 255)
        imgs.append((im, x0, y0))
    # pack in rows up to 512 px wide
    poses_out = []
    W = 512
    cx = cy = rowh = 0
    for im, ox, oy in imgs:
        if cx + im.width > W:
            cx = 0; cy += rowh; rowh = 0
        poses_out.append([cx, cy, im.width, im.height, ox, oy])
        cx += im.width; rowh = max(rowh, im.height)
    atlas = Image.new("RGBA", (max(1, min(W, max(p[0] + p[2] for p in poses_out))), cy + rowh))
    for (im, _, _), p in zip(imgs, poses_out):
        atlas.paste(im, (p[0], p[1]))
    atlas.save(f"{OUT}/{name}.png")
    return {"poses": poses_out, "anims": [[anims[a] for a in g] for g in groups]}


# ------------------------------------------------------------------ effect-object (efob) sprites
# Red's ground emotes are effects 88..94 (effect_data.c gUnknown_80B9CC4): animType 2, efob001, animId 0..6,
# palette = OBJ slot unk8 (monster palet 0 / 3 / 11). efob files hold raw AX data + one static tile strip.
EMOTES = {88: (0, 0, False), 89: (1, 0, False), 90: (2, 3, True), 91: (3, 3, False), 92: (4, 0, False),
          93: (5, 11, True), 94: (6, 11, True)}


def parse_raw(cfile):
    src = open(cfile).read()
    poses = {}
    for m in re.finditer(r"const ax_pose (\w+)\[\] = \{(.*?)\n\};", src, re.S):
        pcs = []
        for e in re.finditer(r"\{ (-?\d+), \{ (-?\d+), (-?\d+) \}, (\d+), (\d+), (\d+) \}", m.group(2)):
            sp, u0, u1, f1, f2, f3 = (int(v) for v in e.groups())
            if f1 == 0xFFFF and f2 == 0xFFFF:
                break
            pcs.append(dict(sprite=sp, shape=f1 >> 14, size=f2 >> 14, ry=(f1 & 0x3FF) - 512, rx=(f2 & 0x1FF) - 256,
                            hf=(f2 >> 12) & 1, vf=(f2 >> 13) & 1, unk1=(f2 >> 9) & 7, tile=f3 & 0x3FF, pal=f3 >> 12))
        poses[m.group(1)] = pcs
    anims = {}
    for m in re.finditer(r"const ax_anim (\w+)\[\] = \{(.*?)\n\};", src, re.S):
        fr = []
        for e in re.finditer(r"\{ (\d+),\s+(\d+),\s+(-?\d+), \{ (-?\d+), (-?\d+) \}", m.group(2)):
            if int(e.group(1)) == 0:
                break
            fr.append([int(e.group(3)), int(e.group(1)), int(e.group(4)), int(e.group(5))])
        anims[m.group(1)] = fr
    def arr(sym):
        m = re.search(r"const ax_\w+ \*const (?:\*const )?" + sym + r"\[\] = \{(.*?)\};", src, re.S)
        return re.findall(r"(\w+),", m.group(1))
    efo = re.search(r"const EfoFileData \w+ = \{\s*(\w+),\s*(\w+),", src)
    pose_list = arr(efo.group(1))
    groups = [arr(t) for t in arr(efo.group(2))]
    return pose_list, poses, groups, anims


def render_pose(placed, vram):
    x0 = min(q[3] for q in placed); y0 = min(q[4] for q in placed)
    x1 = max(q[3] + q[1] for q in placed); y1 = max(q[4] + q[2] for q in placed)
    im = Image.new("RGBA", (x1 - x0, y1 - y0))
    px = im.load()
    for p, w, h, rx, ry, pal in reversed(placed):
        tw = w // 8
        for ty in range(h // 8):
            for tx in range(tw):
                ti = p["tile"] + ty * tw + tx
                if ti >= len(vram):
                    continue
                t = vram[ti]
                for yy in range(8):
                    for xx in range(8):
                        c = t[yy][xx]
                        if c == 0:
                            continue
                        dx = tx * 8 + xx; dy = ty * 8 + yy
                        if p["hf"]: dx = w - 1 - dx
                        if p["vf"]: dy = h - 1 - dy
                        r, g, b = pal[c]
                        px[rx - x0 + dx, ry - y0 + dy] = (r, g, b, 255)
    return im, x0, y0


def pack(name, imgs):
    poses_out = []
    W = 512
    cx = cy = rowh = 0
    for im, ox, oy in imgs:
        if cx + im.width > W:
            cx = 0; cy += rowh; rowh = 0
        poses_out.append([cx, cy, im.width, im.height, ox, oy])
        cx += im.width; rowh = max(rowh, im.height)
    atlas = Image.new("RGBA", (max(1, min(W, max(p[0] + p[2] for p in poses_out))), cy + rowh))
    for (im, _, _), p in zip(imgs, poses_out):
        atlas.paste(im, (p[0], p[1]))
    atlas.save(f"{OUT}/{name}.png")
    return poses_out


def effect_table():
    src = open(f"{RED}/src/effect_data.c").read()
    body = src[src.index("gUnknown_80B9CC4[448]"):]
    tab = {}
    for m in re.finditer(r"\[(\d+)\] = \{\.animType = (\d+), \.effectId = (\d+), \.unk8 = (\d+), \.animId = (\d+), \.unk10 = (-?\d+), \.unk14 = (-?\d+), \.unk18 = (\d+), \.unk1c = (-?\d+), \.unk20 = (-?\d+), \.loop = (-?\d+)\}", body):
        i = int(m.group(1))
        if i in tab:
            break
        tab[i] = [int(x) for x in m.groups()[1:]]
    return tab


def used_effect_ids():
    s = json.load(open(os.path.join(CM.DATA, "ground", "scripts.json")))  # gen_ground_scripts.py output
    ids = set(range(88, 95)) | {318}   # 318: job client rescued (dungeon_jobs.c sub_8042A34)
    for v in s.values():
        for c in v:
            if c[0] == 0x56 and c[3]:
                ids.add(int(c[3]))
    return sorted(ids)


_raw_cache = {}


def build_effects(data):
    """fx<id> for every effect id the ground scripts use (CMD 0x56 -> lives/objects/effects f38)."""
    tab = effect_table()
    for eid in used_effect_ids():
        anim_type, file_id, palslot, anim, sfx, _, _, posset, _, loop = tab[eid]
        if anim_type == 4:
            continue        # efbg full-screen effects: not used by ground scripts
        cfile = f"{RED}/src/data/effects/efob{file_id:03d}.c"
        if cfile not in _raw_cache:
            _raw_cache[cfile] = (parse_raw(cfile), tiles_of_png(f"{RED}/data/effects/efob{file_id:03d}.png"),
                                 jasc(f"{RED}/data/effects/efob{file_id:03d}.pal"))
        (pose_list, poses, groups, anims), vram, file_pal = _raw_cache[cfile]
        def palette(n):
            return file_pal if n == 14 else mon_pal(min(n, 13))
        n_dirs = 8 if len(groups) % 8 == 0 and anim + 8 <= len(groups) else 1
        seqs = [anims[groups[anim + d][0]] for d in range(n_dirs)]
        used = sorted({fr[0] for sq in seqs for fr in sq})
        imgs = []
        for pi in used:
            placed = []
            for p in poses[pose_list[pi]]:
                w, h = SIZES[(p["shape"], p["size"])]
                pal = palette(p["pal"]) if (p["unk1"] & 2) and p["pal"] != 13 else palette(palslot)
                placed.append((p, w, h, p["rx"], p["ry"], pal))
            imgs.append(render_pose(placed, vram) if placed else (Image.new("RGBA", (1, 1)), 0, 0))
        remap = {pi: i for i, pi in enumerate(used)}
        data["fx%d" % eid] = {"poses": pack("fx%d" % eid, imgs), "loop": bool(loop), "sfx": sfx, "posset": posset,
                              "anims": [[[[remap[fr[0]], fr[1], fr[2], fr[3]] for fr in sq] for sq in seqs]]}


import glob
HFILES = sorted(glob.glob(f"{RED}/src/data/ornament/*.h")) + [f"{RED}/src/data/ax/statue.h"]


def main():
    os.makedirs(OUT, exist_ok=True)
    data = {}
    for name in KINDS:
        sym = name[:-1] if name.endswith("p") else name
        sym = "gAx" + sym[0].upper() + sym[1:]
        h = next(f for f in HFILES if re.search(r"const SiroArchive " + sym + r" =", open(f).read()))
        data[name] = build(name, h)
    build_effects(data)
    json.dump(data, open(f"{OUT}/ornaments.json", "w"), separators=(",", ":"))
    print(len(data), "ornaments")


if __name__ == "__main__":
    main()
