#!/usr/bin/env python3
"""Render every PMD Red Rescue Team ground-map background (map_bg) to PNG.

Follows the pret/pmd-red decompilation:
  src/ground_bg.c   sub_80A2FBC (load), CopyBpcTilesToVram, _UncompressCell,
                    BmaLayerNrlDecompressor, sub_80A4764/sub_80A49E8 (animation)
  src/ground_map.c  SubStruct_52C configs, GroundMap_Select, sub_80A5204 (collision),
                    sub_80A4D48 (sprite priority)
  src/ground_sprite.c GroundSprite_Reset (OAM priority 2 or 3)

Usage: python3 -I gen_ground_bg.py [--decomp DIR] [--out DIR] [--no-hd] [--only name1,name2]
"""
import argparse
import json
import os
import re
import struct
import sys
import types

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

DECOMP = common.PMDRED
OUT = os.path.join(common.TMP, 'ground_bg')     # intermediate renders; gen_ground_assets.py copies what the game uses
HD_SCALE = 4


# --------------------------------------------------------------------------- tables
def parse_tables(decomp):
    hdr = open(os.path.join(decomp, 'include/map_files_table.h')).read()
    body = hdr[hdr.index('enum {'):]
    enum = []
    for m in re.finditer(r'(MAP_FILE_ID_[A-Z0-9_]+)', body):
        if m.group(1) == 'MAP_FILE_ID_COUNT':
            break
        enum.append(m.group(1))
    ids = {n: i for i, n in enumerate(enum)}

    src = open(os.path.join(decomp, 'src/map_files_table.c')).read()
    table = {}
    for m in re.finditer(r'\n\s*\[(MAP_FILE_ID_[A-Z0-9_]+)\]\s*=\s*\{(.*?)\n\s*\},', src, re.S):
        blk = m.group(2)

        def field(f):
            mm = re.search(r'\.' + f + r'\s*=\s*(NULL|"([^"]*)")', blk)
            return mm.group(2) if mm and mm.group(1) != 'NULL' else None
        bpa = re.search(r'\.bpaFileNames\s*=\s*\{([^}]*)\}', blk).group(1)
        bpas = [None if t.strip() == 'NULL' else t.strip().strip('"') for t in bpa.split(',')]
        bpas = (bpas + [None] * 4)[:4]
        table[m.group(1)] = dict(bpl=field('bplFileName'), bpc=field('bpcFileName'),
                                 bma=field('bmaFileName'), bpa=bpas)

    # map types from the ground map conversion table (per MAP_* -> MAP_FILE_ID_*)
    conv = open(os.path.join(decomp, 'src/ground_map_conversion_table.c')).read()
    types_by_file = {}
    for m in re.finditer(r'\n\s*\[(MAP_[A-Z0-9_]+)\]\s*=\s*\{(.*?)\n\s*\},', conv, re.S):
        t = re.search(r'\.unk0\s*=\s*(-?\w+)', m.group(2))
        f = re.search(r'\.mapFileTableId\s*=\s*(MAP_FILE_ID_[A-Z0-9_]+)', m.group(2))
        if t and f:
            types_by_file.setdefault(f.group(1), []).append((m.group(1), int(t.group(1), 0)))

    # file name (as used by the game's archive) -> path, from the INCBINs
    files = {}
    srcdir = os.path.join(decomp, 'src')
    for fn in os.listdir(srcdir):
        if fn.startswith('ground_map_files'):
            for m in re.finditer(r'gFile(\w+)\[\]\s*=\s*INCBIN_U8\("([^"]+)"\)', open(os.path.join(srcdir, fn)).read()):
                files[m.group(1)] = os.path.join(decomp, m.group(2))
    return enum, ids, table, types_by_file, files


def parse_dungeon_info(decomp):
    """Data needed to describe dungeon-tileset ground maps (map type 0xA/0xB, sub_80A3440/sub_80ADD9C)."""
    gm = open(os.path.join(decomp, 'src/ground_map.c')).read()
    tbl = gm[gm.index('sMapToDungeonTable[] = {'):]
    tbl = tbl[:tbl.index('};')]
    map_to_dungeon = {}
    for m in re.finditer(r'\.id\s*=\s*(MAP_[A-Z0-9_]+),\s*\.loc\s*=\s*\{\s*\.id\s*=\s*(DUNGEON_[A-Z0-9_]+),\s*\.floor\s*=\s*(\d+)\s*\},\s*\.unk8\s*=\s*(\d+)', tbl):
        map_to_dungeon[m.group(1)] = (m.group(2), int(m.group(3)), int(m.group(4)))
    dh = open(os.path.join(decomp, 'include/constants/dungeon.h')).read()
    dids = {m.group(1): int(m.group(2)) for m in re.finditer(r'(DUNGEON_[A-Z0-9_]+)\s*=\s*(\d+)', dh)}
    di = open(os.path.join(decomp, 'src/dungeon_info.c')).read()
    fc = di[di.index('sDungeonFloorCount[] = {'):]
    fc = fc[:fc.index('};')]
    floor_count = {m.group(1): int(m.group(2)) for m in re.finditer(r'\[(DUNGEON_[A-Z0-9_]+)\]\s*=\s*(\d+)', fc)}
    dd = os.path.join(decomp, 'data/dungeon')
    dirs = re.findall(r'#include "(\w+)/floor_id.inc"', open(os.path.join(dd, 'floor_id.inc')).read())
    # global FloorProperties table (28-byte records): per-dungeon includes + inline bytes, in order
    main = bytearray()
    for line in open(os.path.join(dd, 'main_data.inc')):
        line = line.strip()
        mi = re.match(r'#include "([^"]+)"', line)
        if mi:
            for l2 in open(os.path.join(dd, mi.group(1))):
                if l2.strip().startswith('.byte'):
                    main += bytes(int(x, 0) for x in l2.strip()[5:].split(','))
        elif line.startswith('.byte'):
            main += bytes(int(x, 0) for x in line[5:].split(','))
    dsrc = open(os.path.join(decomp, 'src/dungeon_data.c')).read()
    wt = dsrc[dsrc.index('gDungeonWaterType['):]
    wt = re.findall(r'DUNGEON_WATER_TYPE_(\w+)', wt[:wt.index('};')])
    return dict(map_to_dungeon=map_to_dungeon, dids=dids, floor_count=floor_count, dirs=dirs,
                main=bytes(main), water=wt, dd=dd)


def resolve_dungeon(dinfo, dname, floor):
    """sub_80ADD9C: clamp floor to [1, floorCount-1], look up the floor's tileset in mapparam."""
    did = min(dinfo['dids'][dname], 62)
    cnt = dinfo['floor_count'].get(dname, 1) if did <= 62 else 1
    eff = max(1, floor)
    if eff >= cnt:
        eff = cnt - 1
    res = dict(effective_floor=eff, tileset=None, water_tileset=None)
    try:
        tables = json.load(open(os.path.join(dinfo['dd'], dinfo['dirs'][did], 'floor_id.json')))['tables']
        md = tables[eff - 1]['MainData']   # floor_id.json lists floors 1..count-1
        ts = dinfo['main'][md * 28 + 2]
        res['tileset'] = ts
        res['water_tileset'] = (ts < len(dinfo['water']) and dinfo['water'][ts] == 'WATER')
    except Exception as ex:  # noqa
        res['tileset_error'] = repr(ex)
    return res


def process_dungeon_map(name, entry, mid, map_types, files, out, dinfo):
    """Map types 0xA/0xB are drawn by sub_80A3440 -> sub_80ADD9C with the dungeon tileset.
    BMA layer 0 (the chunk-mapping layer, 64 wide) is the terrain grid fed to sub_80ADFB8."""
    bma = open(files[entry['bma']], 'rb').read()
    h, layers, coll = load_bma(bma)
    maps = [m for m, t in map_types if t in (10, 11)]
    dname, floor, unk8 = dinfo['map_to_dungeon'].get(maps[0], ('DUNGEON_TINY_WOODS', 100, 0))  # table default
    rd = resolve_dungeon(dinfo, dname, floor)
    terr = layers[0][:h['h_chunks'], :h['w_chunks']]
    tname = f'{name}_terrain.json'
    with open(os.path.join(out, tname), 'w') as f:
        json.dump(terr.tolist(), f, separators=(',', ':'))
    cname = f'{name}_collision.json'
    with open(os.path.join(out, cname), 'w') as f:
        json.dump(coll.tolist(), f, separators=(',', ':'))
    oob = 3 if rd.get('water_tileset') else 0
    info = dict(id=mid, dungeon_map=True, ground_maps=maps, dungeon=dname, floor=floor,
                effective_floor=rd['effective_floor'], tileset=rd['tileset'], emap_variant=unk8,
                w=h['w_chunks'], h=h['h_chunks'], unit=24, w_px=h['w_tiles'] * 8, h_px=h['h_tiles'] * 8,
                terrain=tname, terrain_values={'0': 'wall (autotiled by wall neighbours, cex block 0x000)',
                                               '1': 'floor (autotiled by non-wall neighbours, cex block 0x200)',
                                               '2': 'secondary terrain e.g. water/lava (autotiled with same value, cex block 0x100)',
                                               '3': 'secondary terrain, alt (same rule as 2; used as out-of-bounds value on water tilesets)'},
                out_of_bounds=oob,
                fixed_emap=(rd['tileset'] is not None and rd['tileset'] >= 64),
                files=dict(bpl=entry['bpl'], bpc=entry['bpc'], bma=entry['bma']), map_types=sorted(set(t for _, t in map_types)),
                layers=[], above_layer=None, collision_unit=8, collision=cname,
                collision_layers=h['n_coll'], has_data_layer=bool(h['has_data'] > 0), anim={})
    return info


# GroundMap_Select: which ground_map.c mode is applied after loading (sub_80A3BB0 arg)
MAP_MODE = {
    'MAP_PERSONALITY_TEST_CYAN': 4, 'MAP_PERSONALITY_TEST_PURPLE': 4, 'MAP_PERSONALITY_TEST_MULTICOLOR': 4,
    'MAP_FUGITIVES_BLIZZARD_ROAD': 1, 'MAP_FUGITIVES_SNOW_ROAD': 1, 'MAP_SUMMIT_SUNSET': 1,
    'MAP_NIGHTMARE': 4, 'MAP_NIGHT_SKY_2': 1, 'MAP_SILENT_CHASM_ENTRY': 4, 'MAP_NIGHT_SKY_1': 4,
    'MAP_PELIPPER_POST_OFFICE': 3, 'MAP_FRIEND_AREA_FINAL_ISLAND': 3, 'MAP_TITLE_SCREEN': 3,
}


# GroundMap_Select: BLDALPHA value (gUnknown_2026E4E, EVA = high byte, EVB = low byte) for 2-layer maps.
# Ground mode uses BLDCNT table entry 2: target 1 = BG2 (layer 0 / _hi), target 2 = BG3, OBJ, backdrop.
MAP_BLEND = {'MAP_PERSONALITY_TEST_CYAN': 0x808, 'MAP_PERSONALITY_TEST_PURPLE': 0x808,
             'MAP_PERSONALITY_TEST_MULTICOLOR': 0x808, 'MAP_COMET': 0x1010, 'MAP_NIGHTMARE': 0x80C,
             'MAP_SILENT_CHASM_ENTRY': 0x1010}


# --------------------------------------------------------------------------- decoders
def u16(b, o):
    return b[o] | (b[o + 1] << 8)


def s16(b, o):
    return struct.unpack_from('<h', b, o)[0]


def rgb(c):
    # palette entries are 8-bit RGB (+pad), stored as (c5 << 3) | 7; the hardware keeps c >> 3
    # (SetBGPaletteBufferColorArray). Raw 8-bit values are used, matching the reference renders.
    return (c[0], c[1], c[2])


def load_bpl(data, max_pals):
    num_pals = data[0]
    has_anim = data[2]
    pal = np.zeros((16, 16, 4), np.uint8)
    pal[:, :, 3] = 255
    pal[:, 1:, :3] = 255           # unused rows: black + 15 white (sub_80A2FBC)
    o = 4
    for i in range(16):
        pal[i, 0, :3] = 0
    for i in range(num_pals):
        for j in range(15):
            if i < max_pals:
                pal[i, j + 1, :3] = rgb(data[o:o + 3])
            o += 4
    anim = None
    if has_anim:
        specs_off = 4 + num_pals * 60
        apal = specs_off + num_pals * 4
        anim = []
        for i in range(num_pals):
            dur = s16(data, specs_off + i * 4)
            nfr = s16(data, specs_off + i * 4 + 2)
            frames = []
            if nfr > 0 and i < max_pals:
                for f in range(nfr):
                    frames.append([rgb(data[apal + (f * 15 + j) * 4: apal + (f * 15 + j) * 4 + 3]) for j in range(15)])
            if nfr > 0:
                apal += nfr * 60
            anim.append(dict(palette=i, duration=dur, frames=frames))
        anim = [a for a in anim if a['frames']]
    return pal, num_pals, anim


def decode_tiles_4bpp(raw, n):
    a = np.frombuffer(raw[:n * 32], np.uint8).reshape(n, 8, 4)
    out = np.empty((n, 8, 8), np.uint8)
    out[:, :, 0::2] = a & 0xF
    out[:, :, 1::2] = a >> 4
    return out


def load_bpc(data, vram_tiles):
    cw, ch, num_tiles = u16(data, 0), u16(data, 2), u16(data, 4)
    slots = [u16(data, 6 + 2 * k) for k in range(4)]
    num_chunks = u16(data, 14)
    o = 16
    vram = np.zeros((1024, 8, 8), np.uint8)
    # CopyBpcTilesToVram: tile 0 blank, 1..numTiles-1 from file, then 0xFFFF up to unk6
    vram[1:num_tiles] = decode_tiles_4bpp(data[o:], num_tiles - 1)
    vram[num_tiles:vram_tiles] = 0xF
    o += (num_tiles - 1) * 32
    if (cw, ch) not in ((2, 2), (3, 3)):
        raise ValueError('cell type error %d %d' % (cw, ch))
    n = cw * ch
    cells = np.zeros((max(num_chunks, 1), n), np.uint16)
    raw = np.frombuffer(data[o:o + (num_chunks - 1) * n * 2], '<u2')
    cells[1:num_chunks] = raw.reshape(num_chunks - 1, n)
    return dict(cw=cw, ch=ch, num_tiles=num_tiles, slots=slots, num_chunks=num_chunks, vram=vram, cells=cells)


def load_bma(data):
    h = dict(w_tiles=data[0], h_tiles=data[1], tiling_w=data[2], tiling_h=data[3],
             w_chunks=data[4], h_chunks=data[5], layers=u16(data, 6),
             has_data=s16(data, 8), n_coll=s16(data, 10))
    o = 12
    layers = []
    for _ in range(h['layers']):
        rows = []
        prev = None
        for j in range(h['h_chunks']):
            row = []
            k = 0
            while k < h['w_chunks']:
                cmd = data[o]; o += 1
                if cmd >= 0xC0:
                    for _l in range(cmd - 0xBF):
                        v = data[o] | (data[o + 1] << 8) | (data[o + 2] << 16); o += 3
                        row += [v & 0xFFF, (v >> 12) & 0xFFF]
                    k += (cmd - 0xBF) * 2
                elif cmd >= 0x80:
                    v = data[o] | (data[o + 1] << 8) | (data[o + 2] << 16); o += 3
                    row += [v & 0xFFF, (v >> 12) & 0xFFF] * (cmd - 0x7F)
                    k += (cmd - 0x7F) * 2
                else:
                    row += [0, 0] * (cmd + 1)
                    k += (cmd + 1) * 2
            row = (row + [0] * 64)[:64]
            if prev is not None:   # rows after the first are XORed with the row above
                row = [a ^ b for a, b in zip(row, prev)]
            rows.append(row)
            prev = row
        layers.append(np.array(rows, np.int32).reshape(h['h_chunks'], 64))
    coll, o = decode_collision(data, o, h)
    h['bytes_left'] = len(data) - o   # sanity: should be 0..3 (alignment padding)
    return h, layers, coll


def decode_collision(data, o, h):
    """sub_80A5204 (ground_map.c). Returns per-8x8-tile byte grid:
    low bits = data layer byte, bit 0x80 = collision layer 1 (CheckMapCollision_80A585C: solid),
    bit 0x40 = collision layer 2."""
    W, H = h['w_tiles'], h['h_tiles']
    g = np.zeros((H, W), np.uint8)
    if h['has_data'] > 0:
        prev = None
        for r in range(H):
            row = []
            while len(row) < W:
                cmd = data[o]; o += 1
                if cmd >= 0xC0:
                    n = cmd - 0xBF
                    lit = list(data[o:o + n]); o += n
                    row += [b ^ (prev[len(row) + i] if prev else 0) for i, b in enumerate(lit)]
                elif cmd >= 0x80:
                    v = data[o]; o += 1
                    n = cmd - 0x7F
                    row += [v ^ (prev[len(row) + i] if prev else 0) for i in range(n)]
                else:
                    n = cmd + 1
                    row += [(prev[len(row) + i] if prev else 0) for i in range(n)]
            row = row[:W] if len(row) <= 256 - 5 else row
            # the game writes past W into the row padding which is then overwritten by 0xFF; ignore extra
            prev = (row + [0] * 256)[:256]
            g[r] = row[:W]
    for layer, bit in ((0, 0x80), (1, 0x40)):
        if h['n_coll'] <= layer:
            break
        prevbits = None
        for r in range(H):
            bits = []
            while len(bits) < W:
                cmd = data[o]; o += 1
                if cmd > 0x7F:
                    n = cmd - 0x7F
                    if prevbits is None:
                        bits += [1] * n
                    else:
                        bits += [1 - prevbits[len(bits) + i] if len(bits) + i < len(prevbits) else 1 for i in range(n)]
                else:
                    n = cmd + 1
                    if prevbits is None:
                        bits += [0] * n
                    else:
                        bits += [prevbits[len(bits) + i] if len(bits) + i < len(prevbits) else 0 for i in range(n)]
            prevbits = bits
            for c in range(W):
                if bits[c]:
                    g[r, c] |= bit
    return g, o


def load_bpa(data):
    n_tiles = data[0]
    n_frames = s16(data, 2)
    durs = [struct.unpack_from('<i', data, 4 + 4 * i)[0] for i in range(n_frames)]
    return dict(n_tiles=n_tiles, n_frames=n_frames, durations=durs, tiles_off=4 + 4 * n_frames)


# --------------------------------------------------------------------------- rendering
def build_tilemap(layer, cells, cw, ch, h):
    """chunk mapping (64-wide) -> GBA tilemap entries for the whole map (tiles)."""
    hc, wc = h['h_chunks'], h['w_chunks']
    idx = layer[:hc, :wc]
    idx = np.clip(idx, 0, cells.shape[0] - 1)          # chunk ids >= numChunks read zero-filled cells
    t = cells[idx]                                      # (hc, wc, cw*ch)
    t = t.reshape(hc, wc, ch, cw).transpose(0, 2, 1, 3).reshape(hc * ch, wc * cw)
    return t


def render_tilemap(tm, vram, pal, w_px, h_px):
    tile = tm & 0x3FF
    hf = (tm >> 10) & 1
    vf = (tm >> 11) & 1
    pl = (tm >> 12) & 0xF
    px = vram[tile]                                      # (H, W, 8, 8)
    px = np.where(hf[:, :, None, None] == 1, px[:, :, :, ::-1], px)
    px = np.where(vf[:, :, None, None] == 1, px[:, :, ::-1, :], px)
    Ht, Wt = tm.shape
    ci = (pl[:, :, None, None].astype(np.int32) * 16 + px).transpose(0, 2, 1, 3).reshape(Ht * 8, Wt * 8)
    flat = pal.reshape(256, 4)
    img = flat[ci].copy()
    img[(ci & 0xF) == 0, 3] = 0                          # colour 0 of every BG palette is transparent
    out = np.zeros((h_px, w_px, 4), np.uint8)
    hh, ww = min(h_px, img.shape[0]), min(w_px, img.shape[1])
    out[:hh, :ww] = img[:hh, :ww]
    return out


def save(arr, path):
    Image.fromarray(arr, 'RGBA').save(path, optimize=False, compress_level=6)


_xbrz = None


def get_xbrz():
    global _xbrz
    if _xbrz is None:
        _xbrz = common.xbrz_module()
    return _xbrz


def save_hd(arr, path):
    img = Image.fromarray(arr, 'RGBA')
    # xBRZ blends RGB of fully-transparent pixels; zero them so edges don't pick up stray colours
    a = arr.copy()
    a[a[:, :, 3] == 0] = 0
    hd = get_xbrz().scale_pillow(Image.fromarray(a, 'RGBA'), HD_SCALE)
    hd.save(path, compress_level=6)


# --------------------------------------------------------------------------- per map
def process(name, entry, mid, map_types, files, out, hd):
    def rd(fname):
        return open(files[fname], 'rb').read()

    mtypes = sorted(set(t for _, t in map_types))
    two_layer_cfg = any(t in (5, 6, 7, 8, 9) for t in mtypes)
    bma_data = rd(entry['bma'])
    h, layers, coll = load_bma(bma_data)
    if not map_types:
        two_layer_cfg = h['layers'] == 2
    # SubStruct_52C: 2-layer config -> 14 palettes / 0x400 tiles; 1-layer -> 13 palettes / 0x380 tiles
    max_pals, vram_tiles = (14, 0x400) if two_layer_cfg else (13, 0x380)
    pal, num_pals, pal_anim = load_bpl(rd(entry['bpl']), max_pals)
    bpc = load_bpc(rd(entry['bpc']), vram_tiles)
    vram = bpc['vram']

    # BPA slots (sub_80A2FBC): slots 0,1 animate, slots 2,3 are copied once (frame 0)
    vptr = bpc['num_tiles']
    tile_anims = []
    for sid in range(4):
        fn = entry['bpa'][sid]
        if fn is None:
            continue
        b = rd(fn)
        bpa = load_bpa(b)
        nt = bpc['slots'][sid]
        if nt == 0:
            continue
        frames = []
        for f in range(bpa['n_frames'] if sid < 2 else 1):
            off = bpa['tiles_off'] + f * nt * 32
            frames.append(decode_tiles_4bpp(b[off:off + nt * 32], nt))
        end = min(vptr + nt, 1024)
        vram[vptr:end] = frames[0][:end - vptr]
        if sid < 2:
            tile_anims.append(dict(slot=sid, file=fn, first_tile=vptr, num_tiles=nt,
                                   frames=frames, durations=bpa['durations']))
        vptr += nt

    W, H = h['w_tiles'] * 8, h['h_tiles'] * 8
    tilemaps = [build_tilemap(layers[i], bpc['cells'], bpc['cw'], bpc['ch'], h) for i in range(len(layers))]

    info = dict(id=mid, w=W, h=H, files=dict(bpl=entry['bpl'], bpc=entry['bpc'], bma=entry['bma'],
                                             bpa=[x for x in entry['bpa'] if x]),
                map_types=mtypes, chunk=f"{bpc['cw']}x{bpc['ch']}")
    # layer 0 -> BG2 (priority 2), layer 1 -> BG3 (priority 3); 1-layer config uses BG3 only
    if len(layers) == 1:
        layer_names = [f'{name}.png']
    else:
        layer_names = [f'{name}_hi.png', f'{name}_lo.png']
    imgs = []
    for i, tm in enumerate(tilemaps):
        img = render_tilemap(tm, vram, pal, W, H)
        imgs.append(img)
        save(img, os.path.join(out, layer_names[i]))
        if hd:
            save_hd(img, os.path.join(out, layer_names[i].replace('.png', '_hd.png')))
    # draw order bottom->top
    info['layers'] = list(reversed(layer_names))
    # sprites: OAM priority 2 for map types 5 and 8, else 3 (GroundSprite_Reset / sub_80A4D48).
    # OBJ wins ties, so prio-3 sprites sit between BG2 (layer 0) and BG3 (layer 1).
    sprite_prio = 2 if (mtypes and all(t in (5, 8) for t in mtypes)) else 3
    info['sprite_priority'] = sprite_prio
    info['above_layer'] = layer_names[0] if (len(layers) == 2 and sprite_prio == 3) else None
    modes = sorted(set(MAP_MODE.get(m, 0) for m, _ in map_types)) if map_types else [0]
    if len(layers) == 2 and any(m >= 2 for m in modes):
        md = max(modes)
        info['parallax'] = dict(mode=md, note='layers scroll independently (sub_80A3BB0 modes 2-4)',
                                wrap={layer_names[0]: md == 4, layer_names[1]: md != 2})
    if len(layers) == 2:
        bl = max((MAP_BLEND.get(m, 0x1000) for m, _ in map_types), default=0x1000)
        eva, evb = (bl >> 8) & 0x1F, bl & 0x1F
        info['blend'] = dict(layer=layer_names[0], eva=eva, evb=evb,
                             formula='out = min(1, hi*eva/16 + below*evb/16) where hi is opaque; '
                                     'eva=16,evb=0 means plain opaque drawing')
    if len(layers) == 2 and any(m >= 2 for m in modes):
        pass
    elif any(m == 1 for m in modes):
        info['parallax'] = dict(mode=1, note='single render context, wraps around', wrap=True)

    # collision
    cname = f'{name}_collision.json'
    with open(os.path.join(out, cname), 'w') as f:
        json.dump(coll.tolist(), f, separators=(',', ':'))
    info['collision_unit'] = 8
    info['collision'] = cname
    info['collision_layers'] = h['n_coll']
    info['has_data_layer'] = bool(h['has_data'] > 0)

    # animation
    anim = {}
    if tile_anims or pal_anim:
        anim = write_anim(name, out, tilemaps, layer_names, vram, pal, tile_anims, pal_anim, W, H)
    info['anim'] = anim
    return info


def map_state(name, decomp=DECOMP):
    """Decoded map for other tools (gen_town.py): dict(tilemaps (layer 0 = upper/BG2 first), vram, pal,
    tile_anims, pal_anim, W, H) exactly as process() renders it."""
    enum, ids, table, types_by_file, files = parse_tables(decomp)
    e = 'MAP_FILE_ID_' + name.upper()
    entry, map_types = table[e], types_by_file.get(e, [])

    def rd(fname):
        return open(files[fname], 'rb').read()
    mtypes = sorted(set(t for _, t in map_types))
    two_layer_cfg = any(t in (5, 6, 7, 8, 9) for t in mtypes)
    h, layers, coll = load_bma(rd(entry['bma']))
    if not map_types:
        two_layer_cfg = h['layers'] == 2
    max_pals, vram_tiles = (14, 0x400) if two_layer_cfg else (13, 0x380)
    pal, num_pals, pal_anim = load_bpl(rd(entry['bpl']), max_pals)
    bpc = load_bpc(rd(entry['bpc']), vram_tiles)
    vram = bpc['vram']
    vptr = bpc['num_tiles']
    tile_anims = []
    for sid in range(4):
        fn = entry['bpa'][sid]
        if fn is None:
            continue
        b = rd(fn)
        bpa = load_bpa(b)
        nt = bpc['slots'][sid]
        if nt == 0:
            continue
        frames = []
        for f in range(bpa['n_frames'] if sid < 2 else 1):
            off = bpa['tiles_off'] + f * nt * 32
            frames.append(decode_tiles_4bpp(b[off:off + nt * 32], nt))
        end = min(vptr + nt, 1024)
        vram[vptr:end] = frames[0][:end - vptr]
        if sid < 2:
            tile_anims.append(dict(slot=sid, first_tile=vptr, num_tiles=nt, frames=frames,
                                   frame_ticks=[d + 1 for d in bpa['durations']]))
        vptr += nt
    W, H = h['w_tiles'] * 8, h['h_tiles'] * 8
    tilemaps = [build_tilemap(layers[i], bpc['cells'], bpc['cw'], bpc['ch'], h) for i in range(len(layers))]
    return dict(tilemaps=tilemaps, vram=vram, pal=pal, tile_anims=tile_anims, pal_anim=pal_anim or [], W=W, H=H)


MAX_PAL_OVERLAY_FRAMES = 32


def _overlay(img, mask_cells, W, H):
    """Keep only pixels of the masked 8x8 cells; crop to their bounding box. Returns (crop, [x, y]) or None."""
    ys, xs = np.nonzero(mask_cells)
    if len(ys) == 0:
        return None
    m = np.zeros((H, W), bool)
    big = np.repeat(np.repeat(mask_cells, 8, 0), 8, 1)
    m[:min(H, big.shape[0]), :min(W, big.shape[1])] = big[:H, :W]
    x0, y0 = xs.min() * 8, ys.min() * 8
    x1, y1 = min(W, (xs.max() + 1) * 8), min(H, (ys.max() + 1) * 8)
    if x0 >= W or y0 >= H:
        return None
    o = img.copy()
    o[~m] = 0
    return o[y0:y1, x0:x1], [int(x0), int(y0)]


def write_anim(name, out, tilemaps, layer_names, vram, pal, tile_anims, pal_anim, W, H):
    """Animation export.
    tiles (BPA slots 0/1): for every frame and every layer that uses the slot, an overlay PNG holding
      only the 8x8 cells whose tile lies in the slot's VRAM range, cropped to their bounding box;
      draw it at 'pos' over the base layer PNG. Frame f lasts frame_ticks[f] game frames (60 Hz).
    palettes (BPL palette animation): per palette row, the 15 colours of each frame (index 1..15) and,
      when the cycle has <= 32 frames, cropped overlays exactly like the tile animation. Every layer
      also has <layer>_idx.png (8-bit L image, value = palette_row*16 + colour, 0 mod 16 = transparent)
      plus 'base_palette' so a shader can recolour any frame."""
    res = {'tiles': [], 'palettes': []}
    for ta in tile_anims:
        lo, hi = ta['first_tile'], ta['first_tile'] + ta['num_tiles']
        entry = dict(slot=ta['slot'], bpa=ta['file'], vram_tiles=[lo, hi],
                     # sub_80A4764: unk4-- <= 0 -> frame f is shown for durations[f]+1 game frames
                     durations=ta['durations'], frame_ticks=[d + 1 for d in ta['durations']], frames=[])
        masks = [((tm & 0x3FF) >= lo) & ((tm & 0x3FF) < hi) for tm in tilemaps]
        for f, fr in enumerate(ta['frames']):
            v = vram.copy()
            v[lo:lo + len(fr)] = fr
            files = {}
            for li, tm in enumerate(tilemaps):
                ov = _overlay(render_tilemap(tm, v, pal, W, H), masks[li], W, H)
                if ov is None:
                    continue
                fn = layer_names[li].replace('.png', f'_bpa{ta["slot"]}_f{f}.png')
                save(ov[0], os.path.join(out, fn))
                files[layer_names[li]] = dict(file=fn, pos=ov[1])
            entry['frames'].append(files)
        if any(entry['frames']):
            res['tiles'].append(entry)
    if pal_anim:
        res['base_palette'] = [['#%02x%02x%02x' % tuple(pal[r, c, :3]) for c in range(16)] for r in range(16)]
        res['index_images'] = {}
        for li, tm in enumerate(tilemaps):
            tile = tm & 0x3FF
            px = vram[tile]
            px = np.where(((tm >> 10) & 1)[:, :, None, None] == 1, px[:, :, :, ::-1], px)
            px = np.where(((tm >> 11) & 1)[:, :, None, None] == 1, px[:, :, ::-1, :], px)
            ci = (((tm >> 12) & 0xF)[:, :, None, None].astype(np.int32) * 16 + px)
            Ht, Wt = tm.shape
            ci = ci.transpose(0, 2, 1, 3).reshape(Ht * 8, Wt * 8)
            o = np.zeros((H, W), np.uint8)
            o[:min(H, ci.shape[0]), :min(W, ci.shape[1])] = ci[:H, :W]
            fn = layer_names[li].replace('.png', '_idx.png')
            Image.fromarray(o, 'L').save(os.path.join(out, fn))
            res['index_images'][layer_names[li]] = fn
        for pa in pal_anim:
            p = pa['palette']
            masks = [((tm >> 12) & 0xF) == p for tm in tilemaps]
            if not any(m.any() for m in masks):
                continue
            # sub_80A4764: every 'duration' ticks the next frame's 15 colours replace palette row p (loops)
            e = dict(palette=p, duration=pa['duration'], frame_ticks=pa['duration'],
                     colors=[['#%02x%02x%02x' % tuple(c) for c in fr] for fr in pa['frames']], frames=[])
            if len(pa['frames']) <= MAX_PAL_OVERLAY_FRAMES:
                for f, fr in enumerate(pa['frames']):
                    pp = pal.copy()
                    pp[p, 1:, :3] = np.array(fr, np.uint8)
                    files = {}
                    for li, tm in enumerate(tilemaps):
                        ov = _overlay(render_tilemap(tm, vram, pp, W, H), masks[li], W, H)
                        if ov is None:
                            continue
                        fn = layer_names[li].replace('.png', f'_pal{p}_f{f}.png')
                        save(ov[0], os.path.join(out, fn))
                        files[layer_names[li]] = dict(file=fn, pos=ov[1])
                    e['frames'].append(files)
            res['palettes'].append(e)
        if not res['palettes']:
            for k in ('palettes', 'base_palette', 'index_images'):
                res.pop(k, None)
            for fn in os.listdir(out):
                pass
    return {k: v for k, v in res.items() if v}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--decomp', default=DECOMP)
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--no-hd', action='store_true')
    ap.add_argument('--only', default='')
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    enum, ids, table, types_by_file, files = parse_tables(a.decomp)
    dinfo = parse_dungeon_info(a.decomp)
    only = set(x for x in a.only.split(',') if x)
    index, failed = {}, {}
    idx_path = os.path.join(a.out, 'index.json')
    if only and os.path.exists(idx_path):
        index = json.load(open(idx_path))
    for e in enum:
        name = e[len('MAP_FILE_ID_'):].lower()
        if only and name not in only:
            continue
        ent = table.get(e)
        try:
            if ent is None or not ent['bpl'] or not ent['bpc'] or not ent['bma']:
                raise ValueError('incomplete gMapFilesTable entry: %r' % (ent,))
            for k in ('bpl', 'bpc', 'bma'):
                if ent[k] not in files:
                    raise FileNotFoundError(ent[k])
            mt = types_by_file.get(e, [])
            if mt and all(t in (10, 11) for _, t in mt):
                index[name] = process_dungeon_map(name, ent, ids[e], mt, files, a.out, dinfo)
                print('dun %-48s %3dx%-3d cells %s floor %d ts %s' % (name, index[name]['w'], index[name]['h'],
                      index[name]['dungeon'], index[name]['effective_floor'], index[name]['tileset']))
                continue
            index[name] = process(name, ent, ids[e], mt, files, a.out, not a.no_hd)
            print('ok  %-48s %4dx%-4d layers=%d' % (name, index[name]['w'], index[name]['h'], len(index[name]['layers'])))
        except Exception as ex:  # noqa
            failed[name] = repr(ex)
            print('FAIL', name, ex)
    with open(idx_path, 'w') as f:
        json.dump(index, f, indent=1)
    if failed:
        with open(os.path.join(a.out, 'failed.json'), 'w') as f:
            json.dump(failed, f, indent=1)
    print('rendered %d, failed %d' % (len(index), len(failed)))


if __name__ == '__main__':
    main()
