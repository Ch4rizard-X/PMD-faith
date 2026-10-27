#!/usr/bin/env python3
"""The walkable town (Pokemon Square, Post Office, Makuhita Dojo, Whiscash Pond, team bases) for scripts/town/town.gd:
game/assets/town/* and game/data/town.json, built from Red's own ground maps in the pret/pmd-red decomp.

  pictures   the ground map (gen_ground_bg.map_state: data/map_bg *.bpl/.bpc/.bma/.bpa) rendered with all its layers
             at animation frame 0, xBRZ 3x, lossless WebP (k = 3). Team bases use the "basic" house.
  anim       the map's own animation (BPA tile slots 0/1 + BPL palette cycling, ticked at 60 Hz exactly like
             sub_80A4764): every change over one common period becomes a frame; 'd' lists the 8x8 tiles that
             change going into the next frame with their picture in anim_<map>.webp (tiles cut from the xBRZ 3x
             frame, deduplicated, 64 per row). Format as AnimLayer in town.gd expects.
  grid       walkable 4 px cells: Red's collision layer (bit 0x80 = solid, sub_80A5204) plus the remake's
             hand-placed OPEN patches (paths into the yards / the Dojo maze entrance the remake adds).
  flags.png  the 32 team flags (flag00p..flag16p, flag100p..flag114p ornaments, gen_ornaments.py) 6 frames each.
  LAYOUT     the remake's own town design (spawn points, NPC stalls, interaction areas, exits, music) - authored
             data of this project, kept here as source.
"""
import json
import base64
import math
import os
import sys

import numpy as np
from PIL import Image

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.join(TOOLS, "ground"))
import common  # noqa: E402
import gen_ground_bg as GB  # noqa: E402

OUT = os.path.join(common.ASSETS, "town")
K = 3
PERIOD_CAP = 3600            # ticks (60 s): longest animation period baked into a town map
GROUND = {"square": ("pokemon_square", "pokemon_square"), "post_office": ("pelipper_post_office", "post_office"),
          "dojo": ("makuhita_dojo", "makuhita_dojo"), "whiscash": ("whiscash_pond", "whiscash_pond")}
BASES = {"0001": "bulbasaur", "0004": "charmander", "0007": "squirtle", "0025": "pikachu", "0155": "cyndaquil",
         "0258": "mudkip", "0066": "cubone"}
FLAGS = ["flag%02dp" % i for i in range(17)] + ["flag%dp" % (100 + i) for i in range(15)]
# walkable patches [x0, y0, x1, y1] (px) on top of Red's collision
OPEN = {
    "square": [[700, 486, 774, 534]],
    "whiscash": [[216, 222, 242, 320]],                         # stepping stones out to Whiscash's rock
    "dojo": [[480, 264, 560, 300], [560, 284, 648, 384], [520, 340, 648, 384]],   # path to the Dojo maze exits
    "0066": [[258, 200, 296, 300], [262, 286, 292, 318], [200, 222, 360, 292]],
    "0004": [[190, 222, 365, 286], [260, 204, 294, 224], [262, 284, 292, 312], [254, 296, 300, 322]],
    "0155": [[190, 222, 365, 286], [260, 204, 294, 224], [262, 284, 292, 312], [254, 296, 300, 322]],
    "0001": [[198, 212, 358, 280], [258, 200, 292, 224], [262, 278, 292, 312]],
    "0007": [[262, 204, 292, 254], [240, 270, 310, 324], [150, 222, 218, 264], [214, 226, 340, 264], [148, 188, 170, 312],
             [334, 222, 400, 264], [380, 188, 402, 312]],
    "0258": [[262, 204, 292, 254], [240, 270, 310, 324], [150, 222, 218, 264], [214, 226, 340, 264], [148, 188, 170, 312],
             [334, 222, 400, 264], [380, 188, 402, 312]],
}

# the remake's town design (positions in map pixels; f = facing 0..7)
LAYOUT = {'maps': {'square': {'music': '007',
                     'spawn': [520, 356, 0],
                     'npcs': [{'id': 'kecleon_shop',
                               'sp': '0352',
                               'x': 285,
                               'y': 245,
                               'f': 0,
                               'reach': [266, 256, 299, 292]},
                              {'id': 'kecleon_wares',
                               'sp': '0352p',
                               'x': 314,
                               'y': 245,
                               'f': 0,
                               'reach': [299, 256, 332, 292]},
                              {'id': 'persian_bank',
                               'sp': '0053',
                               'x': 658,
                               'y': 268,
                               'f': 0,
                               'reach': [622, 292, 702, 324]},
                              {'id': 'kangaskhan_storage',
                               'sp': '0115',
                               'x': 335,
                               'y': 500,
                               'f': 0,
                               'reach': [298, 512, 372, 532]},
                              {'id': 'gulpin_shop',
                               'sp': '0316',
                               'x': 661,
                               'y': 490,
                               'f': 0,
                               'reach': [622, 506, 702, 528]},
                              {'id': 'wigglytuff',
                               'sp': '0040',
                               'x': 783,
                               'y': 268,
                               'f': 0,
                               'reach': [748, 292, 818, 324]}],
                     'spots': [{'id': 'nohome', 'reach': [376, 262, 420, 284]}],
                     'blocks': [],
                     'exits': [{'r': [495, 0, 545, 6], 'to': 'whiscash', 'back': [520, 18, 0]},
                               {'r': [0, 302, 8, 342], 'to': 'base', 'back': [18, 322, 2]},
                               {'r': [520, 708, 560, 720], 'to': 'dojo', 'back': [540, 694, 4]},
                               {'r': [950, 302, 960, 342], 'to': 'post_office', 'back': [936, 322, 6]}],
                     'arrive': {'post_office': [936, 322, 6],
                                'dojo': [540, 694, 4],
                                'whiscash': [520, 18, 0],
                                'base': [18, 322, 2]},
                     'xblocks': []},
          'post_office': {'music': '007',
                          'spawn': [22, 322, 2],
                          'npcs': [{'id': 'pelipper_board',
                                    'sp': '0279',
                                    'x': 386,
                                    'y': 276,
                                    'f': 0,
                                    'reach': [350, 262, 424, 312]}],
                          'spots': [{'id': 'pelipper_board', 'reach': [266, 300, 326, 322]}],
                          'blocks': [],
                          'exits': [{'r': [0, 300, 8, 342], 'to': 'square', 'back': [22, 322, 2]}],
                          'arrive': {'square': [22, 322, 2]},
                          'xblocks': []},
          'dojo': {'music': '110',
                   'spawn': [372, 18, 0],
                   'npcs': [{'id': 'makuhita_dojo',
                             'sp': '0296',
                             'x': 278,
                             'y': 238,
                             'f': 0,
                             'reach': [252, 246, 304, 272]}],
                   'spots': [],
                   'blocks': [],
                   'exits': [{'r': [350, 0, 395, 6], 'to': 'square', 'back': [372, 18, 0]},
                             {'r': [640, 280, 648, 384], 'to': 'dojo_maze', 'back': [618, 330, 6]},
                             {'r': [520, 376, 648, 384], 'to': 'dojo_maze', 'back': [590, 356, 4]}],
                   'arrive': {'square': [372, 18, 0]},
                   'xblocks': []},
          'whiscash': {'music': '007',
                       'spawn': [231, 600, 4],
                       'npcs': [{'id': 'whiscash',
                                 'sp': '0340',
                                 'x': 229,
                                 'y': 204,
                                 'f': 0,
                                 'reach': [206, 212, 252, 250]}],
                       'spots': [],
                       'blocks': [],
                       'exits': [{'r': [200, 616, 262, 624], 'to': 'square', 'back': [231, 600, 4]}],
                       'arrive': {'square': [231, 600, 4]},
                       'xblocks': []},
          'base': {'music': '001',
                   'spawn': [276, 250, 0],
                   'npcs': [],
                   'spots': [{'id': 'bed', 'reach': [250, 210, 302, 234]},
                             {'id': 'mailbox', 'reach': [228, 260, 280, 294]}],
                   'blocks': [[252, 268, 9]],
                   'exits': [{'r': [544, 305, 552, 398], 'to': 'square', 'back': [536, 352, 6]},
                             {'r': [0, 305, 8, 398], 'to': 'friend_areas', 'back': [22, 350, 2]},
                             {'r': [236, 544, 308, 552], 'to': 'world_map', 'back': [272, 530, 4]}],
                   'arrive': {'square': [536, 352, 6]}}},
 'bases': {'0001': {'xblocks': []},
           '0004': {'xblocks': [[200, 272, 12], [357, 272, 12]]},
           '0007': {'xblocks': []},
           '0025': {'xblocks': []},
           '0155': {'xblocks': [[200, 272, 12], [357, 272, 12]]},
           '0258': {'xblocks': []},
           '0066': {'xblocks': []}},
 'base_shape': {'0152': '0001',
                '0252': '0001',
                '0255': '0155',
                '0133': '0025',
                '0052': '0025',
                '0300': '0025',
                '0158': '0007',
                '0054': '0007',
                '0104': '0066'},
 'follow_gap': 30,
 'speed': 84,
 'flag': {'tex': 'flags.png', 'x': 198, 'y': 116, 'w': 32, 'h': 32, 'frames': 6, 'ms': 140}}


# ----------------------------------------------------------------------------------- rendering
def _compose(st, vram, pal):
    """all layers, bottom (last tilemap = BG3) to top (BG2)"""
    out = None
    for tm in reversed(st["tilemaps"]):
        img = GB.render_tilemap(tm, vram, pal, st["W"], st["H"])
        if out is None:
            out = img.copy()
        else:
            m = img[..., 3] > 0
            out[m] = img[m]
    return out


def _timeline(st):
    """[(state, ticks)] over one common period: state = (bpa frame per slot, palette frame per row)"""
    cycles = []
    for ta in st["tile_anims"]:
        cycles.append([t for t in ta["frame_ticks"]])
    for pa in st["pal_anim"]:
        cycles.append([max(1, pa["duration"])] * len(pa["frames"]))
    if not cycles:
        return []
    period = 1
    for c in cycles:
        period = period * sum(c) // math.gcd(period, sum(c))
    period = min(period, PERIOD_CAP)

    def frame_at(c, t):
        t %= sum(c)
        for i, d in enumerate(c):
            if t < d:
                return i
            t -= d
        return 0
    out = []
    for t in range(period):
        s = tuple(frame_at(c, t) for c in cycles)
        if out and out[-1][0] == s:
            out[-1][1] += 1
        else:
            out.append([s, 1])
    if len(out) > 1 and out[-1][0] == out[0][0]:
        out[0][1] += out.pop()[1]
    return out


def _render_state(st, s):
    vram = st["vram"].copy()
    pal = st["pal"].copy()
    k = 0
    for ta in st["tile_anims"]:
        fr = ta["frames"][s[k]]
        vram[ta["first_tile"]:ta["first_tile"] + len(fr)] = fr
        k += 1
    for pa in st["pal_anim"]:
        pal[pa["palette"], 1:, :3] = np.array(pa["frames"][s[k]], np.uint8)
        k += 1
    return _compose(st, vram, pal)


def _hd(arr):
    a = arr.copy()
    a[a[..., 3] == 0] = 0
    return np.array(common.xbrz_scale(Image.fromarray(a, "RGBA"), K))


def _webp(arr, name):
    Image.fromarray(arr, "RGBA").save(common.p(OUT, name), "WEBP", lossless=True, quality=100, method=4)


def picture(ground, out_name):
    st = GB.map_state(ground)
    base = _compose(st, st["vram"], st["pal"])
    e = {"w": st["W"], "h": st["H"], "tex": out_name + ".webp", "k": K}
    _webp(_hd(base), out_name + ".webp")
    tl = _timeline(st)
    if len(tl) > 1:
        e["anim"] = anim(st, tl, out_name)
    return e, st


def anim(st, tl, out_name, T=8, per=64):
    W, H = st["W"], st["H"]
    tw = W // T
    frames = [_render_state(st, s) for s, _ in tl]
    n = len(frames)
    atlas_tiles, index = [], {}
    d = []
    for i in range(n):
        a, b = frames[i], frames[(i + 1) % n]
        ch = np.nonzero((a != b).any(axis=2).reshape(H // T, T, tw, T).any(axis=(1, 3)))
        up = None
        lst = []
        for ty, tx in zip(*ch):
            if up is None:
                up = _hd(b)
            tile = up[ty * T * K:(ty + 1) * T * K, tx * T * K:(tx + 1) * T * K]
            key = tile.tobytes()
            if key not in index:
                index[key] = len(atlas_tiles)
                atlas_tiles.append(tile)
            lst += [int(ty * tw + tx), index[key]]
        d.append(lst)
    rows = (len(atlas_tiles) + per - 1) // per
    atlas = np.zeros((rows * T * K, per * T * K, 4), np.uint8)
    for j, t in enumerate(atlas_tiles):
        atlas[(j // per) * T * K:(j // per + 1) * T * K, (j % per) * T * K:(j % per + 1) * T * K] = t
    _webp(atlas, "anim_%s.webp" % out_name)
    # 60 Hz ticks -> ms, rounded on the running total so the lap length stays exact
    dur, acc = [], 0
    for _, ticks in tl:
        dur.append(int(round((acc + ticks) * 1000 / 60.0)) - int(round(acc * 1000 / 60.0)))
        acc += ticks
    return {"t": T, "tw": tw, "per": per, "dur": dur, "d": d, "atlas": "anim_%s.webp" % out_name, "k": K}


def grid(st, ground, key, C=4):
    coll = None
    path = os.path.join(common.TMP, "ground_bg", ground + "_collision.json")
    if os.path.exists(path):
        coll = np.array(json.load(open(path)), np.uint8)
    else:                       # same data straight from the map (gen_ground_bg.process writes it)
        raise SystemExit("missing %s (run gen_ground_bg.py first)" % path)
    W, H = st["W"] // C, st["H"] // C
    walk = np.repeat(np.repeat((coll & 0x80) == 0, 8 // C, 0), 8 // C, 1)[:H, :W]
    for x0, y0, x1, y1 in OPEN.get(key, []):
        walk[y0 // C:-(-y1 // C), x0 // C:-(-x1 // C)] = True
    bits = np.packbits(walk.ravel().astype(np.uint8), bitorder="little")
    return {"C": C, "W": W, "H": H, "b64": base64.b64encode(bits.tobytes()).decode()}


def flags():
    orn = os.path.join(common.ASSETS, "ground", "orn")
    rows = [np.array(Image.open(common.need(os.path.join(orn, f + ".png"), "ornament " + f)).convert("RGBA"))
            for f in FLAGS]
    Image.fromarray(np.concatenate(rows, axis=0), "RGBA").save(common.p(OUT, "flags.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    data = json.loads(json.dumps(LAYOUT))
    for key, (ground, name) in GROUND.items():
        e, st = picture(ground, name)
        e["grid"] = grid(st, ground, key)
        data["maps"][key].update(e)
        print("town", key, e["w"], e["h"], "anim frames", len(e.get("anim", {}).get("dur", [])), flush=True)
    for shape, sp in BASES.items():
        ground = "team_base_%s_basic" % sp
        e, st = picture(ground, "base_" + sp)
        e["grid"] = grid(st, ground, shape)
        e["xblocks"] = data["bases"][shape].get("xblocks", [])
        data["bases"][shape] = e
        print("base", shape, sp, "anim frames", len(e.get("anim", {}).get("dur", [])), flush=True)
    flags()
    common.save_json(os.path.join(common.DATA, "town.json"), data)
    print("town.json", os.path.getsize(os.path.join(common.DATA, "town.json")), "bytes")


if __name__ == "__main__":
    main()
