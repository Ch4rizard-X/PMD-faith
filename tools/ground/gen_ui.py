#!/usr/bin/env python3
"""UI graphics from Red's ROM (archives addressed as in the pret/pmd-red decomp) -> game/assets/ui/.

  cursors.png         fontsp OBJ tiles 0-15 (system archive) with fontpal row 0 (graphics_memory.c)
  hudfont.png         'font' tiles 0x40-0x46 ("F", "Lv", "HP/", "B") + 0x10-0x19 (digits), fontpal row 0
  dmg_red / dmg_blue  hp5font (dungeon archive, floating damage digits + "MISS") with monster palettes 6 / 0
  dmg_digits.png      hp5font in palettes 3 (yellow), 10 (green), 6 (red)  [graphics/ax/pal/N.pal]
  mode_arrows.png     etcfont OBJ tiles 18-20 (direction-mode arrows), monster palette 0
  rank_badges.png     tmrkpat (team rank badges, code_801D014.c) 7 x 16x16 with its palette, colour 0 clear
  legend_icons.png    clmkpat (load_screen.c DrawQuestIcons) 12 x 16x16 with sLegendaryQuestIconPalNums
  traps_red.png       trappat (code_803DA7C_2.c sub_803E02C): 29 traps of 3x3 BG tiles, palette 12/13 by
                      gUnknown_80F5F70 (dungeon_config.c)
  stairs.png          trap 22 (the stairs) of the same sheet
  mode_grid / mode_hilite  traps 20 / 21 (the direction-mode grid square and its highlighted version)
  menu_artwork_1..3   titlen0..2 title-menu backgrounds (titlemenu archive: BG2 over BG3, 240x160)
  slider_on/off.png   4x8 option-slider pips (drawn here; the remake's own UI element, not ROM art)
  pmd_red_text.ttf    Red's text font (kanji_a, text_2.c glyph format) as a TrueType pixel font: 1 px = 100
                      units, 11 px em, baseline under row 8; code < 0x80 -> ASCII, 0x80-0xFF -> cp1252 when
                      defined, everything else (incl. NBSP/soft hyphen and the Japanese/symbol codes) -> U+E000 +
                      glyph index (so 0xBD/0xBE = ♂/♀ sit at ½/¾ and e.g. ♂ glyph E101 as the game notes)
  logo_transparent.png  title logo from the titleop1/titleop2 ornaments (see gen_logo)
"""
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import common  # noqa: E402
import redfs as R  # noqa: E402
from ttf_writer import write_ttf  # noqa: E402

OUT = os.path.join(common.ASSETS, "ui")
B = 0x08000000
SYSTEM, TITLEMENU, DUNGEON = 0x08300500, 0x08380000, 0x083B0000
FONT, FONTPAL, FONTSP, KANJI_A = 0x302024, 0x30612C, 0x30632C, 0x30F66C   # system archive files (gen_front_assets)


def rom():
    return R.rom()


def u32(o):
    return struct.unpack_from("<I", rom(), o)[0]


def u16(o):
    return struct.unpack_from("<H", rom(), o)[0]


def tiles(buf):
    n = len(buf) // 32
    t = np.frombuffer(bytes(buf[:n * 32]), np.uint8).reshape(n, 8, 4)
    px = np.empty((n, 8, 8), np.uint8)
    px[:, :, 0::2] = t & 15
    px[:, :, 1::2] = t >> 4
    return px


def rom_pal(o, n=16, clear0=True):
    p = np.array([(rom()[o + 4 * i], rom()[o + 4 * i + 1], rom()[o + 4 * i + 2], 255) for i in range(n)], np.uint8)
    if clear0:
        p[0::16] = (0, 0, 0, 0)
    return p


def ax_pal(n, clear0=True):
    L = open(os.path.join(common.PMDRED, "graphics", "ax", "pal", "%d.pal" % n)).read().split("\n")[3:19]
    p = np.array([tuple(int(v) for v in l.split()) + (255,) for l in L], np.uint8)
    if clear0:
        p[0] = (0, 0, 0, 0)
    return p


def sheet(tile_px, layout, pal):
    """layout: rows of tile indices (None = empty) -> RGBA array"""
    h, w = len(layout) * 8, max(len(r) for r in layout) * 8
    out = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(layout):
        for x, t in enumerate(row):
            if t is not None:
                out[y * 8:y * 8 + 8, x * 8:x * 8 + 8] = pal[tile_px[t]]
    return out


def save(arr, name):
    Image.fromarray(arr, "RGBA").save(common.p(OUT, name))


def file_data(arch, name):
    """file data offset (after SIRO deref) in the ROM"""
    return R.Archive(arch).raw(name)


def counted_tiles(o):
    """u32 count + 4bpp tiles (font, fontsp, etcfont, hp5font)"""
    n = u32(o)
    return tiles(rom()[o + 4:o + 4 + 32 * n])


def ptr_tiles(o, n=None):
    """FileStruct2 {s32 count; u8 tiles[]} (itempat, trappat ...)"""
    return counted_tiles(o)


# ----------------------------------------------------------------------------------- tile sheets
def gen_tiles():
    fp0 = rom_pal(FONTPAL)
    save(sheet(counted_tiles(FONTSP), [list(range(16))], fp0), "cursors.png")
    font = tiles(rom()[FONT + 4:FONT + 4 + 32 * 0x80])
    save(sheet(font, [list(range(0x40, 0x47)) + list(range(0x10, 0x1A))], fp0), "hudfont.png")
    hp5 = counted_tiles(file_data(DUNGEON, "hp5font"))
    row = list(range(16))
    save(sheet(hp5, [row], ax_pal(6)), "dmg_red.png")
    save(sheet(hp5, [row], ax_pal(0)), "dmg_blue.png")
    d = np.concatenate([sheet(hp5, [row], ax_pal(n)) for n in (3, 10, 6)], axis=0)
    save(d, "dmg_digits.png")
    etc = counted_tiles(file_data(DUNGEON, "etcfont"))
    save(sheet(etc, [[18, 19, 20]], ax_pal(0)), "mode_arrows.png")
    # team rank badges: {gfx ptr, palette ptr}; badge r = tiles 4r..4r+3 (16x16, row-major 2x2)
    o = file_data(TITLEMENU, "tmrkpat")
    gfx, pal = u32(o) - B, u32(o + 4) - B
    tp = tiles(rom()[gfx:gfx + 32 * 28])
    save(sheet(tp, [[4 * r + k for r in range(7) for k in (0, 1)], [4 * r + k for r in range(7) for k in (2, 3)]],
               rom_pal(pal)), "rank_badges.png")
    # legendary quest icons: 4 palettes (BG 11..14), icon i drawn with sLegendaryQuestIconPalNums[i]
    src = open(os.path.join(common.PMDRED, "src", "load_screen.c")).read()
    tab = src[src.index("sLegendaryQuestIconPalNums"):]
    palnums = [int(v) for v in re.findall(r"\]\s*=\s*(\d+)", tab[:tab.index("};")])]
    o = file_data(TITLEMENU, "clmkpat")
    gfx, pal = u32(o) - B, u32(o + 4) - B
    lp = tiles(rom()[gfx:gfx + 32 * 4 * len(palnums)])
    pals = [rom_pal(pal + 64 * k, clear0=False) for k in range(4)]
    out = np.zeros((16, 16 * len(palnums), 4), np.uint8)
    for i, pn in enumerate(palnums):
        out[:, 16 * i:16 * i + 16] = sheet(lp, [[4 * i, 4 * i + 1], [4 * i + 2, 4 * i + 3]], pals[pn - 11])
    save(out, "legend_icons.png")
    # traps: 29 x 9 BG tiles, palette 12/13
    o = file_data(DUNGEON, "trappat")
    tr = ptr_tiles(u32(o) - B)
    tpal = rom_pal(u32(o + 4) - B, 32)
    dc = open(os.path.join(common.PMDRED, "src", "dungeon_config.c")).read()
    trap_pal = [int(v) for v in re.search(r"gUnknown_80F5F70\[[^\]]*\]\s*=\s*\{([^}]*)\}", dc).group(1).split(",")]

    def trap(i, opaque=False):
        p = tpal[16 * (trap_pal[i] - 12):16 * (trap_pal[i] - 12) + 16].copy()
        if opaque:
            p[0] = tuple(tpal[16 * (trap_pal[i] - 12)][:3]) + (255,)
        return sheet(tr, [[9 * i + 3 * r + c for c in range(3)] for r in range(3)], p)
    save(np.concatenate([trap(i) for i in range(len(trap_pal))], axis=1), "traps_red.png")
    save(trap(22), "stairs.png")
    save(trap(20), "mode_grid.png")
    save(trap(21), "mode_hilite.png")


def gen_sliders():
    for name, (edge, fill) in (("slider_on.png", ((120, 90, 20), (255, 220, 74))),
                               ("slider_off.png", ((40, 44, 70), (70, 78, 110)))):
        a = np.zeros((8, 4, 4), np.uint8)
        a[1:7, 0:3] = edge + (255,)
        a[2:6, 1:2] = fill + (255,)
        save(a, name)


# ----------------------------------------------------------------------------------- title art
def gen_title_art():
    """titlen0..2 (titlemenu archive, titlemenu_sbin.c): AT4PX {2048 u16 BG2+BG3 tilemap, 4bpp tiles},
    palette file titlenNp (224 colours); BG3 drawn first, BG2 on top -> menu_artwork_1..3.png"""
    ns = _gwm()
    A = R.Archive(TITLEMENU)
    for k in range(3):
        o = A.files["titlen%d" % k]
        d = R.at_decompress(o if rom()[o:o + 2] == b"AT" else A.raw("titlen%d" % k))
        tm = [struct.unpack_from("<H", d, i * 2)[0] for i in range(2048)]
        tl = ns["tiles4"](d[0x1000:])
        po = A.raw("titlen%dp" % k)
        pal = [(rom()[po + 4 * i], rom()[po + 4 * i + 1], rom()[po + 4 * i + 2], 255) for i in range(224)]
        out = np.zeros((160, 240, 4), np.uint8)
        for layer in (1, 0):
            m = [[tm[layer * 1024 + y * 32 + x] for x in range(32)] for y in range(32)]
            img = ns["render_bg"](m, tl, pal, 30, 20, 0)
            msk = img[:, :, 3] > 0
            out[msk] = img[msk]
        save(out, "menu_artwork_%d.png" % (k + 1))


def _gwm():
    gwm = os.path.join(os.path.dirname(HERE), "data", "gen_world_map.py")
    src = open(gwm).read().split("def build_map")[0]
    ns = {"__file__": gwm}
    exec(src, ns)
    return ns


# ----------------------------------------------------------------------------------- font
def unicode_of(code, index):
    if 0x20 <= code < 0x7F:
        return code
    if 0x80 <= code <= 0xFF and code not in (0xA0, 0xAD):
        try:
            return ord(bytes([code]).decode("cp1252"))
        except UnicodeDecodeError:
            pass
    return 0xE000 + index


def gen_font():
    hdr = u32(KANJI_A + 4) - B
    cnt, ent = u32(hdr), u32(hdr + 4) - B
    glyphs = []
    for i in range(cnt):
        o = ent + 12 * i
        go, code, w, flags = u32(o) - B, u16(o + 4), struct.unpack_from("<h", rom(), o + 6)[0], rom()[o + 10]
        if flags & 1:
            continue                  # full-colour icons (drawn from glyphs.png by the game)
        pix = set()
        for r in range(12):           # 12 glyph rows; baseline under row 8
            v = u16(go + r * 6) | (u16(go + r * 6 + 2) << 16) | (u16(go + r * 6 + 4) << 32)
            for x in range(12):
                if (v >> (4 * x)) & 15:
                    pix.add((x, r))
        glyphs.append(([unicode_of(code, i)], max(w, 0), pix))
    write_ttf(common.p(OUT, "pmd_red_text.ttf"), glyphs, upm=1100, ascent=900, descent=200, base_row=9, unit=100,
              family="PMD Red Text")
    return len(glyphs)


# ----------------------------------------------------------------------------------- portraits / logo
MONSTER = 0x08510000


def gen_portraits():
    """portraits_emo.png: every kaoNNN (monster archive, PortraitGfx {pal, AT4PX gfx} x 13, 40x40 = 5x5 tiles)
    emotion 2.. (all but Normal / Happy), in file order, 16 per row."""
    A = R.Archive(MONSTER)
    cells = []
    for n in sorted(k for k in A.files if k.startswith("kao")):
        o = A.raw(n)
        for k in range(2, 13):
            pal, gfx = u32(o + 8 * k), u32(o + 8 * k + 4)
            if not pal or not gfx:
                continue
            pal -= B
            gfx -= B
            d = R.at_decompress(gfx) if rom()[gfx:gfx + 2] == b"AT" else rom()[gfx:gfx + 800]
            cells.append(sheet(tiles(d[:800]), [list(range(r * 5, r * 5 + 5)) for r in range(5)],
                               rom_pal(pal, clear0=False)))
    rows = (len(cells) + 15) // 16
    out = np.zeros((rows * 40, 640, 4), np.uint8)
    for j, c in enumerate(cells):
        out[(j // 16) * 40:(j // 16) * 40 + 40, (j % 16) * 40:(j % 16) * 40 + 40] = c
    save(out, "portraits_emo.png")


def gen_logo():
    """logo_transparent.png: the title logo = upper copy in the title_screen ground map's top layer (S02, rendered
    by gen_ground_bg.py into common.TMP/ground_bg), cropped to its bounding box (225x139)."""
    src = os.path.join(common.TMP, "ground_bg", "title_screen_hi.png")
    a = np.array(Image.open(common.need(src, "title_screen_hi.png (run gen_ground_bg.py)")).convert("RGBA"))
    top = a[:a.shape[0] // 2]
    ys, xs = np.nonzero(top[..., 3])
    save(top[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy(), "logo_transparent.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    gen_tiles()
    gen_sliders()
    gen_title_art()
    gen_portraits()
    gen_logo()
    n = gen_font()
    print("ui: tile sheets, title art, font (%d glyphs) -> %s" % (n, OUT))


if __name__ == "__main__":
    main()
