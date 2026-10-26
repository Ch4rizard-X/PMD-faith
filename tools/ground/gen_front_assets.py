#!/usr/bin/env python3
"""Front-end UI graphics from Red's ROM (system archive) for scripts/ui (agent "front").

Sources: pmd-red data/system_sbin.s (font, fontpal, fontsp, fontsppa, kanji_a), src/text_1.c (window border
tiles 0x2D8.. = font tile 0x60..), src/text_2.c DrawCharOnWindowInternal (glyph format), src/game_options.c
SetWindowBGColor (Blue / Red / Green window colours), charmap.txt (special glyph codes).
Outputs in game/assets/ui/front/:
  window.png      Red's window frame as a 24x24 nine-patch (8 px corners), fill = palette index 1 drawn in
                  pure magenta so the game can recolour it (Blue / Red / Green option)
  glyphs.png      special text glyphs (kanji_a icons) in one row; glyphs.json {NAME: [x, width]} (height 12)
  fontsp.png      the 16 OBJ tiles of fontsp (text arrow, menu arrows, saving icon ...) with fontsppa, 128x8
"""
import json, os, struct
import numpy as np
from PIL import Image

ROM = open("/tmp/claude-0/pmdred_full/baserom.gba", "rb").read()
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "game", "assets", "ui", "front")
B = 0x08000000
u32 = lambda o: struct.unpack_from("<I", ROM, o)[0]
u16 = lambda o: struct.unpack_from("<H", ROM, o)[0]
s16 = lambda o: struct.unpack_from("<h", ROM, o)[0]

FONT, FONTPAL, FONTSP, FONTSPPA, KANJI_A = 0x302024, 0x30612C, 0x30632C, 0x306530, 0x30F66C

def pal(o, n):
    return [(ROM[o + 4 * i], ROM[o + 4 * i + 1], ROM[o + 4 * i + 2], 255) for i in range(n)]

def tile(o):
    t = np.zeros((8, 8), np.uint8)
    for y in range(8):
        for x in range(4):
            b = ROM[o + y * 4 + x]
            t[y, 2 * x] = b & 15
            t[y, 2 * x + 1] = b >> 4
    return t

def main():
    os.makedirs(OUT, exist_ok=True)
    fpal = pal(FONTPAL, 128)
    P = np.array(fpal[16:32], np.uint8)          # BG palette 15 = fontpal[16..31] (sub_8099690, male / default)
    P[0] = (0, 0, 0, 0)
    P[1] = (255, 0, 255, 255)                    # window colour (SetFontsBaseColor), recoloured in game
    # --- window frame: corner 0x2D8, top 0x2D9, side 0x2DA, fill 0x2DB (font tile = bg tile - 0x278)
    T = lambda n: tile(FONT + 4 + (n - 0x278) * 32)
    corner, top, side, fill = T(0x2D8), T(0x2D9), T(0x2DA), T(0x2DB)
    rfill = T(0x293)                             # rounded BG1 fill under the corners (ShowWindows a3 = TRUE)
    def lay(base, over):
        o = base.copy()
        m = over != 0
        o[m] = over[m]
        return o
    g = np.zeros((24, 24), np.uint8)
    cells = {(0, 0): corner, (1, 0): top, (2, 0): corner[:, ::-1],
             (0, 1): side, (1, 1): fill, (2, 1): side[:, ::-1],
             (0, 2): corner[::-1, :], (1, 2): top[::-1, :], (2, 2): corner[::-1, ::-1]}
    under = {(0, 0): rfill, (2, 0): rfill[:, ::-1], (0, 2): rfill[::-1, :], (2, 2): rfill[::-1, ::-1]}
    for (cx, cy), t in cells.items():
        g[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8] = lay(under.get((cx, cy), fill), t)    # BG1 fill under BG0 frame
    Image.fromarray(P[g]).save(os.path.join(OUT, "window.png"))
    # --- special glyphs (kanji_a): 12 px wide rows of 3 u16 (4bpp, low nibble = left), 12 rows
    hdr = u32(KANJI_A + 4) - B
    cnt, ent = u32(hdr), u32(hdr + 4) - B
    table = {}
    for i in range(cnt):
        o = ent + 12 * i
        table[u16(o + 4)] = (u32(o) - B, s16(o + 6), ROM[o + 10])
    names = {"POKE_PO": 0x83BF, "POKE_KE": 0x83C4, "ENVELOPE_OPEN": 0x83C0, "THANK_YOU_MAIL": 0x83C1,
             "ICON_GO": 0x83C2, "ICON_NEWS": 0x83C3, "NDS_X_BUTTON": 0x83C6, "NDS_Y_BUTTON": 0x83C7,
             "R_BUTTON": 0x8486, "ENVELOPE_CLOSED": 0x8487, "ICON_BLANK": 0x8740, "ICON_SET": 0x8741,
             "STAR_BULLET": 0x8742, "STAR_SET": 0x8743, "ICON_STICKY": 0x8744, "SPEECH_BUBBLE": 0x8745,
             "HEART_RED_TINY": 0x8746, "HEART_RED_SMALL": 0x8747, "HEART_RED_MEDIUM": 0x8748, "HEART_RED_LARGE": 0x8749,
             "HEART_YELLOW_TINY": 0x874A, "HEART_YELLOW_SMALL": 0x874B, "HEART_YELLOW_MEDIUM": 0x874C,
             "HEART_YELLOW_LARGE": 0x874D, "TM": 0x874E, "ORB": 0x874F, "A_BUTTON": 0x8750, "B_BUTTON": 0x8751,
             "DPAD": 0x8752, "START_BUTTON_1": 0x8753, "START_BUTTON_2": 0x8771, "SELECT_BUTTON_1": 0x8772,
             "SELECT_BUTTON_2": 0x8773, "L_BUTTON": 0x8774}
    GP = np.array(fpal[16:32], np.uint8)
    GP[0] = (0, 0, 0, 0)
    glyphs = []
    meta = {}
    x = 0
    for nm, code in names.items():
        if code not in table:
            continue
        o, w, flags = table[code]
        img = np.zeros((12, 12), np.uint8)
        for r in range(12):
            a, b, c = u16(o + r * 6), u16(o + r * 6 + 2), u16(o + r * 6 + 4)
            v = a | (b << 16) | (c << 32)
            for px in range(12):
                img[r, px] = (v >> (4 * px)) & 15
        if not (flags & 1):
            img = np.where(img != 0, 7, 0).astype(np.uint8)     # plain glyph: ink colour (white)
        rgba = GP[img][:, :max(1, w)]
        glyphs.append(rgba)
        meta[nm] = [x, int(w)]
        x += rgba.shape[1]
    atlas = np.zeros((12, x, 4), np.uint8)
    for (nm, (gx, w)), g2 in zip(meta.items(), glyphs):
        atlas[:, gx:gx + g2.shape[1]] = g2
    Image.fromarray(atlas).save(os.path.join(OUT, "glyphs.png"))
    json.dump(meta, open(os.path.join(OUT, "glyphs.json"), "w"), indent=0)
    # --- fontsp (OBJ tiles 0x3F0-0x3FF) with fontsppa (OBJ palette 15)
    n = u32(FONTSP)
    SP = np.array(pal(FONTSPPA, 16), np.uint8)
    SP[0] = (0, 0, 0, 0)
    strip = np.zeros((8, 8 * n, 4), np.uint8)
    for i in range(n):
        strip[:, i * 8:i * 8 + 8] = SP[tile(FONTSP + 4 + i * 32)]
    Image.fromarray(strip).save(os.path.join(OUT, "fontsp.png"))
    print("window.png, glyphs.png (%d glyphs), fontsp.png -> %s" % (len(meta), OUT))

if __name__ == "__main__":
    main()
