#!/usr/bin/env python3
"""World map / Friend Areas map art and data from Red's ROM (titlemenu archive) for scripts/ui/world_map.gd.

Sources: pmd-red src/world_map.c, src/friend_areas_map*.c, src/titlemenu_sbin.c, data/titlemenu_sbin.s.
Outputs (game/assets/worldmap/, game/data/world_map.json).
"""
import json, os, re, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

DECOMP = common.PMDRED
GAME = common.GAME
OUT = os.path.join(GAME, "assets", "worldmap")
# dungeon / friend-area keys come from data/dungeons.json and data/friend_areas.json (tools/data build);
# PMD_DATA_IN can point at another data folder that has them (only used to read those two key lists)
DATA_IN = os.environ.get("PMD_DATA_IN") or common.DATA
ROM = open(os.path.join(DECOMP, "baserom.gba"), "rb").read()
BASE = 0x08000000

def u16(b, o): return b[o] | (b[o + 1] << 8)
def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def s16(b, o): return struct.unpack_from("<h", b, o)[0]

def at_decompress(src, o=0):
    """decompress_at.c DecompressAT (AT4P / AT3P, 'X' mode)."""
    s = src[o:]
    clen = s[5] | (s[6] << 8)
    if s[:4] == b"AT4P":
        idx = 0x12
    elif s[:4] == b"AT3P":
        idx = 0x10
    else:
        raise ValueError("not AT: %r" % s[:5])
    if s[4] == ord("N"):
        return bytes(s[7:7 + clen])
    flags = [s[7 + i] + 3 for i in range(9)]
    dst = bytearray()
    cmdbit = 8
    cur = 0
    while idx < clen:
        if cmdbit == 8:
            cur = s[idx]; idx += 1; cmdbit = 0
        if (cur & 0x80) == 0:
            command = (s[idx] >> 4) + 3
            tmp = (s[idx] & 0xF) << 8
            for k, f in enumerate(flags):
                if command == f:
                    command = 0x1F - k
            if command >= 0x17:
                c = s[idx] & 0xF; idx += 1
                n = lambda v: v & 0xF
                pat = {0x1F: (c, c, c, c), 0x1E: (c, c + 1, c + 1, c + 1), 0x1D: (c, c - 1, c, c),
                       0x1C: (c, c, c - 1, c), 0x1B: (c, c, c, c - 1), 0x1A: (c, c - 1, c - 1, c - 1),
                       0x19: (c, c + 1, c, c), 0x18: (c, c, c + 1, c), 0x17: (c, c, c, c + 1)}[command]
                dst.append((n(pat[0]) << 4) | n(pat[1]))
                dst.append((n(pat[2]) << 4) | n(pat[3]))
            else:
                idx += 1
                tmp += s[idx]; idx += 1
                p = tmp + len(dst) - 0x1000
                for _ in range(command):
                    dst.append(dst[p]); p += 1
        else:
            dst.append(s[idx]); idx += 1
        cmdbit += 1
        cur = (cur << 1) & 0xFF
    return bytes(dst)

def ptr(o):
    return u32(ROM, o) - BASE

def palette(off, n):
    """RGB_Struct (r, g, b, unk) -> list of (r, g, b, 255)"""
    return [(ROM[off + 4 * i], ROM[off + 4 * i + 1], ROM[off + 4 * i + 2], 255) for i in range(n)]

def tiles4(raw):
    n = len(raw) // 32
    a = np.frombuffer(raw[:n * 32], dtype=np.uint8).reshape(n, 8, 4)
    t = np.zeros((n, 8, 8), dtype=np.uint8)
    t[:, :, 0::2] = a & 0xF
    t[:, :, 1::2] = a >> 4
    return t

def render_bg(tm, tiles, pal, w_t, h_t, tile_base, idx=None):
    img = np.zeros((h_t * 8, w_t * 8, 4), dtype=np.uint8)
    palarr = np.array(pal, dtype=np.uint8)
    for y in range(h_t):
        for x in range(w_t):
            e = tm[y][x]
            ti = (e & 0x3FF) - tile_base
            if ti < 0 or ti >= len(tiles):
                continue
            t = tiles[ti]
            if e & 0x400: t = t[:, ::-1]
            if e & 0x800: t = t[::-1, :]
            pn = (e >> 12) & 0xF
            px = palarr[np.minimum(pn * 16 + t, len(pal) - 1)].copy()
            px[t == 0, 3] = 0
            img[y * 8:y * 8 + 8, x * 8:x * 8 + 8] = px
            if idx is not None:
                sub = idx[y * 8:y * 8 + 8, x * 8:x * 8 + 8]
                sub[t != 0] = (pn * 16 + t)[t != 0]
    return img

def over(dst, src):
    m = src[:, :, 3] > 0
    dst[m] = src[m]

def build_map(prefix, font_off, mcc_sir, pal_off, w_px, h_px, name):
    font = at_decompress(ROM, font_off)
    mcc_data = ptr(mcc_sir + 4)
    mcc = at_decompress(ROM, mcc_data)
    pal = palette(pal_off, 224)
    tiles = tiles4(font)
    tm3 = [[u16(mcc, (y * 64 + x) * 2) for x in range(64)] for y in range(64)]
    tm2 = [[u16(mcc, 0x2000 + (y * 64 + x) * 2) for x in range(64)] for y in range(64)]
    allidx = [e & 0x3FF for row in tm3 + tm2 for e in row]
    print(name, "font", len(font), "tiles", len(tiles), "mcc", len(mcc), "tile idx range", min(allidx), max(allidx))
    base = 0
    w_t, h_t = w_px // 8, h_px // 8
    idx = np.zeros((h_t * 8, w_t * 8), dtype=np.int32)
    a = render_bg(tm3, tiles, pal, w_t, h_t, base, idx)
    b = render_bg(tm2, tiles, pal, w_t, h_t, base, idx)
    out = a.copy()
    out[:, :, 3] = 255
    bgc = np.array(pal[0], dtype=np.uint8)
    out[a[:, :, 3] == 0] = bgc
    over(out, b)
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, name + ".png"))
    return idx

def anim_overlay(idx, cani_sir, first, name):
    """Animated colours (UpdateAnimatedColors(..., cani, first, 16, ...)): a mask of the pixels that use
    palette entries first..first+15 (R = entry*16) and a frames x 16 colour strip."""
    h = ptr(cani_sir + 4)
    cols = []
    dur = 1
    for i in range(16):
        o = ptr(h + 4 * i)
        cnt, dur = s16(ROM, o), s16(ROM, o + 2)
        cols.append([tuple(ROM[o + 4 + 4 * k:o + 7 + 4 * k]) + (255,) for k in range(cnt)])
    n = max(len(c) for c in cols)
    strip = np.zeros((16, n, 4), dtype=np.uint8)
    for i, c in enumerate(cols):
        for k in range(n):
            strip[i, k] = c[k % len(c)] if c else (0, 0, 0, 0)
    Image.fromarray(strip, "RGBA").save(os.path.join(OUT, name + "_anim_pal.png"))
    m = (idx >= first) & (idx < first + 16)
    mask = np.zeros(idx.shape + (4,), dtype=np.uint8)
    mask[..., 0] = np.where(m, (idx - first) * 16 + 8, 0)
    mask[..., 3] = np.where(m, 255, 0)
    Image.fromarray(mask, "RGBA").save(os.path.join(OUT, name + "_anim_mask.png"))
    return {"frames": n, "duration": int(dur)}

# ---------------------------------------------------------------- wmapspr (EfoFileData-like ax file)
OAM_SIZES = {(0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
             (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
             (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64)}

def wmapspr():
    sir = 0x39A304
    hdr = ptr(sir + 4)
    poses_p = ptr(hdr)
    anims_p = ptr(hdr + 4)
    anim_count = u32(ROM, hdr + 8)
    tiles_p = ptr(hdr + 0x14)
    pal_p = ptr(hdr + 0x18)
    tile_count = u32(ROM, hdr + 0x1C)
    print("wmapspr anims", anim_count, "tiles", tile_count, hex(tiles_p), hex(pal_p))
    tiles = tiles4(ROM[tiles_p:tiles_p + 0xD80])
    # the file's own palette (OBJ 15) is a cyan dummy; the markers draw with OBJ palette 0 = monster "palet" slot 0
    # each OAM piece names its OBJ palette (attr2 >> 12): slot n of the monster "palet" (graphics/ax/pal/n.pal),
    # e.g. dungeon markers use slot 3 and the base marker slot 6
    pals = []
    for n in range(14):
        lines = open(os.path.join(DECOMP, "graphics/ax/pal/%d.pal" % n)).read().split("\n")[3:19]
        pals.append(np.array([tuple(int(v) for v in l.split()) + (255,) for l in lines], dtype=np.uint8))
    anims = []
    for ai in range(anim_count):
        dirs_p = ptr(anims_p + 4 * ai)
        seq_p = ptr(dirs_p)          # direction 0 (all 8 point to the same data)
        frames = []
        o = seq_p
        while True:
            nfr = ROM[o]
            if nfr == 0:
                break
            pose = s16(ROM, o + 2)
            ox, oy = s16(ROM, o + 4), s16(ROM, o + 6)
            frames.append((nfr, pose, ox, oy))
            o += 12
        anims.append(frames)
    # render poses into 64x64 cells, origin at (32, 32)
    npose = 15
    sheet = np.zeros((64, 64 * npose, 4), dtype=np.uint8)
    for pi in range(npose):
        lp = ptr(poses_p + 4 * pi)
        o = lp
        while True:
            spr = s16(ROM, o)
            f1, f2, f3 = u16(ROM, o + 4), u16(ROM, o + 6), u16(ROM, o + 8)
            if f1 == 0xFFFF and f2 == 0xFFFF:
                break
            y = f1 & 0xFF
            if y >= 128: y -= 256
            shape = (f1 >> 14) & 3
            x = f2 & 0xFF          # Red sign-extends the low 8 bits (0xF0 = -16)
            if x >= 128: x -= 256
            size = (f2 >> 14) & 3
            hflip = (f2 >> 12) & 1
            vflip = (f2 >> 13) & 1
            tnum = f3 & 0x3FF
            w, h = OAM_SIZES[(shape, size)]
            blk = np.zeros((h, w), dtype=np.uint8)
            k = tnum
            for ty in range(h // 8):
                for tx in range(w // 8):
                    if 0 <= k < len(tiles):
                        blk[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8] = tiles[k]
                    k += 1
            if hflip: blk = blk[:, ::-1]
            if vflip: blk = blk[::-1, :]
            px = pals[min((f3 >> 12) & 0xF, 13)][blk].copy()
            px[blk == 0, 3] = 0
            cx, cy = pi * 64 + 32 + x, 32 + y
            for yy in range(h):
                for xx in range(w):
                    if px[yy, xx, 3] and 0 <= cy + yy < 64 and pi * 64 <= cx + xx < pi * 64 + 64:
                        sheet[cy + yy, cx + xx] = px[yy, xx]
            o += 10
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, "wmapspr.png"))
    return anims

# ---------------------------------------------------------------- data tables from the decomp sources
def dungeon_coords():
    src = open(os.path.join(DECOMP, "src/world_map.c")).read()
    blk = src[src.index("gDungeonCoordinates[] ="):]
    blk = blk[:blk.index("};")]
    out = {}
    for m in re.finditer(r"\[(DUNGEON_\w+)\]\s*=\s*\{(\d+),\s*(\d+)\}", blk):
        out[m.group(1)] = [int(m.group(2)), int(m.group(3))]
    return out

def dungeon_rules():
    d = json.load(open(os.path.join(DECOMP, "data/dungeon/dungeon_data.json")))
    out = {}
    for e in d:
        out[e["name"]] = {
            "max_items": e.get("maxItemsAllowed", 0), "max_party": e.get("maxPartyMembers", 0),
            "level_reset": bool(e.get("levelResetTo1", False)), "keep_money": bool(e.get("keepMoney", False)),
            "no_save": bool(e.get("enterWithoutGameSave", False)), "hm_mask": int(str(e.get("HMMask", "0")), 0),
        }
    return out

def dungeon_enum():
    src = open(os.path.join(DECOMP, "include/constants/dungeon.h")).read()
    names = []
    blk = src[src.index("enum"):]
    blk = blk[:blk.index("}")]
    for line in blk.splitlines():
        m = re.match(r"\s*(DUNGEON_\w+)\s*(=\s*(\w+))?\s*,", line)
        if m:
            names.append(m.group(1))
    return names

def friend_locations():
    src = open(os.path.join(DECOMP, "src/data/friend_areas_map.h")).read()
    hdr = open(os.path.join(DECOMP, "include/friend_areas_map.h")).read()
    locs = re.findall(r"(LOCATION_\w+)\s*,", hdr[hdr.index("enum"):])
    first = src[src.index("{\n    {"):]
    first = first[:first.index("\n    },\n    {")]
    out = []
    for m in re.finditer(r"\[(LOCATION_\w+)\]\s*=\s*\{(.*?)\n        \}", first, re.S):
        body = m.group(2)
        name = re.search(r'\.name = _?\(?"([^"]*)"', body).group(1)
        pos = [int(v, 0) for v in re.search(r"\.pos = \{([^}]*)\}", body).group(1).split(",")]
        areas = [a.strip() for a in re.search(r"\.areasIds = \{([^}]*)\}", body).group(1).split(",")]
        areas = [a for a in areas if a.startswith("FRIEND_AREA_")]
        adj = [-1] * 8
        dirs = ["SOUTH", "SOUTHEAST", "EAST", "NORTHEAST", "NORTH", "NORTHWEST", "WEST", "SOUTHWEST"]
        for dm in re.finditer(r"\[DIRECTION_(\w+)\]\s*=\s*(-?\w+)", body):
            v = dm.group(2)
            adj[dirs.index(dm.group(1))] = locs.index(v) if v.startswith("LOCATION_") else int(v, 0)
        out.append({"id": m.group(1), "name": name, "pos": pos, "areas": areas, "adj": adj})
    order = {n: i for i, n in enumerate(locs)}
    out.sort(key=lambda e: order[e["id"]])
    return out

def main():
    os.makedirs(OUT, exist_ok=True)
    build_map("wmp2", 0x39B814, 0x3A1574, 0x3A2AF4, 480, 320, "red_world_map")
    fidx = build_map("wmap", 0x392B88, 0x398A9C, 0x399F84, 480, 320, "red_friend_map")
    fanim = anim_overlay(fidx, 0x392638, 0xB0, "red_friend_map")
    anims = wmapspr()
    names = dungeon_enum()
    coords = dungeon_coords()
    rules = dungeon_rules()
    keys = list(json.load(open(common.need(os.path.join(DATA_IN, "dungeons.json"), "data/dungeons.json (build tools/data first)")))["dungeons"].keys())
    dun = {}
    for i, n in enumerate(names[:64]):
        if i >= len(keys):
            break
        e = {"enum": n}
        if n in coords: e["pos"] = coords[n]
        if n in rules: e.update(rules[n])
        dun[keys[i]] = e
    fl = friend_locations()
    fa_keys = list(json.load(open(common.need(os.path.join(DATA_IN, "friend_areas.json"), "data/friend_areas.json (build tools/data first)")))["areas"].keys())
    for l in fl:
        ks = []
        for a in l["areas"]:
            k = a[len("FRIEND_AREA_"):].lower().replace("_", "")
            if k == "none":
                ks.append(""); continue          # the team base
            if k not in fa_keys:
                c = [f for f in fa_keys if k.startswith(f)] or [f for f in fa_keys if f.startswith(k[:8])]
                k = max(c, key=len) if c else k
            ks.append(k)
        l["keys"] = ks
    out = {"red": dun, "friend_locations": fl,
           "wmapspr_anims": [[list(f) for f in a] for a in anims], "friend_anim": fanim}
    json.dump(out, open(os.path.join(GAME, "data/world_map.json"), "w"), indent=1)
    print("dungeons", len(dun), "friend locations", len(out["friend_locations"]))



# ================================================================ Explorers of Sky world maps (MAP_BG s01p01a etc.)
EOS = common.EOS

def eos_bpc_image(d, pos, size):
    """skytemple-rust compression/bpc_image.rs BpcImageDecompressor."""
    out = bytearray()
    has_left, left, pattern, pbuf = False, 0, 0, 0
    def g8():
        nonlocal pos
        v = d[pos]; pos += 1; return v
    def g16():
        nonlocal pos
        v = d[pos] | (d[pos + 1] << 8); pos += 2; return v
    while len(out) < size:
        if pos >= len(d):
            if has_left and size - len(out) <= 2:
                out += bytes([left & 0xFF, left >> 8])[:size - len(out)]
                break
            raise ValueError("bpc image short")
        cmd = g8()
        if cmd in (0x7E, 0xFF, 0xBF, 0xDF):
            nb = g8()
        elif cmd == 0x7F:
            nb = g16()
        else:
            nb = cmd
            if cmd >= 0xE0: nb -= 0xE0
            elif cmd >= 0xC0: nb -= 0xC0
            elif cmd >= 0x80: nb -= 0x80
        if has_left:
            nb -= 1
        loading = 0x80 <= cmd < 0xC0
        if loading or cmd >= 0xE0:
            pattern, pbuf = pbuf, pattern
        if loading:
            pattern = g8()
        is_pat = cmd >= 0x80
        if has_left:
            hi = pattern if is_pat else g8()
            v = left | (hi << 8)
            out += bytes([v & 0xFF, (v >> 8) & 0xFF])
            has_left = False
        if nb >= 0:
            if is_pat:
                for _ in range(0, nb, 2):
                    out += bytes([pattern, pattern])
            else:
                for _ in range(0, nb, 2):
                    out += bytes([d[pos], d[pos + 1]]); pos += 2
            if nb % 2 == 0:
                has_left = True
                left = pattern if is_pat else g8()
    return bytes(out[:size]), pos

def eos_bpc_tilemap(d, pos, size):
    """compression/bpc_tilemap.rs: NRL over the high bytes, then the low bytes."""
    out = bytearray()
    while len(out) < size:
        cmd = d[pos]; pos += 1
        if cmd < 0x80:
            for _ in range(cmd + 1): out += b"\0\0"
        elif cmd < 0xC0:
            p = d[pos]; pos += 1
            for _ in range(cmd - 0x7F): out += bytes([0, p])
        else:
            for _ in range(cmd - 0xBF):
                out += bytes([0, d[pos]]); pos += 1
    del out[size:]
    o = 0
    while o < size:
        cmd = d[pos]; pos += 1
        if cmd < 0x80:
            o += (cmd + 1) * 2
        elif cmd < 0xC0:
            p = d[pos]; pos += 1
            for _ in range(cmd - 0x7F):
                out[o] |= p; o += 2
        else:
            for _ in range(cmd - 0xBF):
                out[o] |= d[pos]; pos += 1; o += 2
    return bytes(out), pos

def eos_bpc(d, tw, th):
    up, lo = u16(d, 0), u16(d, 2)
    nl = 2 if lo > 0 else 1
    o = 4
    meta = []
    for _ in range(nl):
        nt = u16(d, o) - 1
        bpas = [u16(d, o + 2 + 2 * k) for k in range(4)]
        clen = u16(d, o + 10)
        meta.append((nt, bpas, clen)); o += 12
    layers = []
    for li, start in enumerate([up, lo][:nl]):
        nt, bpas, clen = meta[li]
        img, p = eos_bpc_image(d, start, nt * 32)
        if p % 2: p += 1
        tm, p = eos_bpc_tilemap(d, p, (clen - 1) * tw * th * 2)
        tiles = np.zeros((1024, 8, 8), np.uint8)
        tiles[1:1 + nt] = tiles4(img)[:min(nt, 1023)]
        cells = np.zeros((clen, tw * th), np.uint16)
        cells[1:] = np.frombuffer(tm, "<u2").reshape(clen - 1, tw * th)
        layers.append(dict(tiles=tiles, cells=cells, bpas=bpas, ntiles=nt))
    return layers

def eos_bma(d):
    wc_cam, hc_cam, tw, th, wch, hch = d[0], d[1], d[2], d[3], d[4], d[5]
    nl = u16(d, 6)
    per = wch * hch * 2 + (hch * 2 if wch % 2 else 0)
    pos = 12
    layers = []
    for _ in range(nl):
        vals = []
        while len(vals) * 2 < per:
            cmd = d[pos]; pos += 1
            if cmd < 0x80:
                vals += [0, 0] * (cmd + 1)
            else:
                n = cmd - 0x7F if cmd < 0xC0 else cmd - 0xBF
                for k in range(n):
                    if cmd < 0xC0 and k > 0:
                        vals += vals[-2:]; continue
                    b0, b1, b2 = d[pos], d[pos + 1], d[pos + 2]; pos += 3
                    vals += [b0 | ((b1 & 0xF) << 8), (b2 << 4) | (b1 >> 4)]
        vals = vals[:per // 2]
        prev = [0] * wch
        lay = []
        i = 0
        skipped = True
        for v in vals:
            if i >= wch * hch: break
            ir = i % wch
            if not skipped and ir == 0 and wch % 2:
                skipped = True; continue
            skipped = False
            cv = v ^ prev[ir]; prev[ir] = cv
            lay.append(cv); i += 1
        layers.append(np.array(lay, np.int32).reshape(hch, wch))
    return dict(w=wc_cam * 8, h=hc_cam * 8, tw=tw, th=th, wch=wch, hch=hch), layers

def eos_bpl(d):
    n = u16(d, 0)
    pal = np.zeros((16, 16, 4), np.uint8); pal[:, :, 3] = 255
    o = 4
    for i in range(n):
        for j in range(15):
            if i < 16: pal[i, j + 1, :3] = list(d[o:o + 3])
            o += 4
    return pal

def eos_render(name):
    rd = lambda ext: open(os.path.join(EOS, "fs/MAP_BG", name + ext), "rb").read()
    h, mlayers = eos_bma(rd(".bma"))
    blayers = eos_bpc(rd(".bpc"), h["tw"], h["th"])
    pal = eos_bpl(rd(".bpl")).reshape(256, 4)
    W, H = h["wch"] * h["tw"] * 8, h["hch"] * h["th"] * 8
    out = np.zeros((H, W, 4), np.uint8)
    out[:, :, :3] = pal[0, :3]; out[:, :, 3] = 255
    for li in reversed(range(len(mlayers))):     # layer 1 (lower) first, layer 0 on top
        # chunk counts show BMA layer 0 uses the second BPC layer section and vice versa
        b = blayers[len(blayers) - 1 - li] if len(blayers) == len(mlayers) else blayers[0]
        idx = np.clip(mlayers[li], 0, len(b["cells"]) - 1)
        t = b["cells"][idx].reshape(h["hch"], h["wch"], h["th"], h["tw"]).transpose(0, 2, 1, 3)
        tm = t.reshape(h["hch"] * h["th"], h["wch"] * h["tw"]).astype(np.int32)
        tile = tm & 0x3FF
        px = b["tiles"][tile]
        hf = ((tm >> 10) & 1)[:, :, None, None] == 1
        vf = ((tm >> 11) & 1)[:, :, None, None] == 1
        px = np.where(hf, px[:, :, :, ::-1], px)
        px = np.where(vf, px[:, :, ::-1, :], px)
        pl = (tm >> 12) & 0xF
        ci = (pl[:, :, None, None] * 16 + px).transpose(0, 2, 1, 3).reshape(tm.shape[0] * 8, tm.shape[1] * 8)
        img = pal[ci]
        m = (ci & 0xF) != 0
        out[m] = img[m]
    print("eos map", name, "size", W, H, "layers", len(mlayers), "bpas", [b["bpas"] for b in blayers])
    return out[:h["h"], :h["w"]] if h["w"] <= W and h["h"] <= H else out

def eos_maps():
    import xml.etree.ElementTree as ET
    xml = open(common.need(common.SKYTEMPLE_XML, "SkyTemple pmd2scriptdata.xml")).read()
    na = xml[xml.index("EoS NA ONLY"):]
    lv = {}
    for m in re.finditer(r'<Level _id="\s*(\d+)" name="(\w+)"', na):
        i = int(m.group(1))
        if i in lv: break
        lv[i] = m.group(2)
    arm9 = open(os.path.join(EOS, "arm9.bin"), "rb").read()
    off = 0x20A94D0 - 0x2000000
    mk = [struct.unpack_from("<hhhh", arm9, off + 8 * i) for i in range(310)]
    # entry 0 = Treasure Town (the start), entry n = dungeon n - 1; ref >= 0 points at another entry
    def resolve(i, depth=0):
        lvl, ref, x, y = mk[i]
        if ref >= 0 and depth < 8:
            r = resolve(ref, depth + 1)
            return r if r else None
        if lvl < 0:
            return None
        return [lv[lvl].lower(), x, y]
    markers = {}
    for i in range(1, 310):
        r = resolve(i)
        if r:
            markers[i - 1] = r
    used = sorted(set(v[0] for v in markers.values()) | {resolve(0)[0]})
    for nm in used:
        img = eos_render(nm)
        if nm == "s01p01a":
            img = img[:336, :504]       # the BMA holds 8 identical 504x336 copies of the map
        Image.fromarray(img, "RGBA").save(os.path.join(OUT, "eos_" + nm + ".png"))
    return {"start": resolve(0), "markers": {str(k): v for k, v in markers.items()}}

if __name__ == "__main__":
    if "--eos" not in sys.argv:          # --eos: only redo the Explorers of Sky maps
        main()
    os.makedirs(OUT, exist_ok=True)
    if common.RED_ONLY:
        sys.exit(0)                      # Red only: no Explorers of Sky world map
    em = eos_maps()
    p = os.path.join(GAME, "data/world_map.json")
    j = json.load(open(p))
    j["eos"] = em
    json.dump(j, open(p, "w"), indent=1)
