"""Red's ending staff credits (credits1.c DrawCredits, gCreditsTable @ 0x80E591C, 27 pages of CreditsData
{s16 type, s16 x, s16 y, text}) -> data/red_credits.json, plus the two title-bracket glyphs (0x82A0 / 0x82A2 of the
kanji_a font) -> assets/ground/credits/bracket_l.png / bracket_r.png."""
import json, struct, sys
import numpy as np
from PIL import Image
ROM = open('/tmp/claude-0/pmdred_full/baserom.gba', 'rb').read()
G = '/tmp/claude-0/pmd1/game/'
B = 0x08000000
u32 = lambda o: struct.unpack_from('<I', ROM, o)[0]
u16 = lambda o: struct.unpack_from('<H', ROM, o)[0]
s16 = lambda o: struct.unpack_from('<h', ROM, o)[0]
FONT_TABLES = [0x30F66C, 0x3191B8]          # kanji_a / kanji_b

def cstr(a):
    a -= B; e = ROM.index(b'\0', a); return ROM[a:e]

def text(b):
    out = ''; i = 0
    while i < len(b):
        c = b[i]
        if b[i:i + 2] == b'#+': out += '{CENTER_ALIGN}'; i += 2; continue
        if c == 0x82 and i + 1 < len(b):
            out += {0xA0: '{BL}', 0xA2: '{BR}'}.get(b[i + 1], '?'); i += 2; continue
        if c == 0x87 and i + 1 < len(b):
            out += '{G%02X}' % b[i + 1]; i += 2; continue
        if c == 0x7E and i + 2 < len(b):          # '~XX': a character by its hex code (text_2.c HexDigitValue)
            out += bytes([int(b[i + 1:i + 3], 16)]).decode('latin1'); i += 3; continue
        out += bytes([c]).decode('latin1'); i += 1
    return out

pages = []
for p in struct.unpack_from('<27I', ROM, 0xE591C):
    a = p - B; recs = []
    while True:
        t, x, y, _, tp = struct.unpack_from('<hhhHI', ROM, a)
        if tp == 0: break
        recs.append([t, x, y, text(cstr(tp))]); a += 12
    pages.append(recs)
json.dump(pages, open(G + 'data/red_credits.json', 'w'), indent=0, ensure_ascii=False)

def glyph(code):
    for ft in FONT_TABLES:
        hdr = u32(ft + 4) - B
        cnt, ent = u32(hdr), u32(hdr + 4) - B
        for i in range(cnt):
            o = ent + 12 * i
            if u16(o + 4) == code:
                go, w = u32(o) - B, s16(o + 6)
                img = np.zeros((12, 12), np.uint8)
                for r in range(12):
                    v = u16(go + r * 6) | (u16(go + r * 6 + 2) << 16) | (u16(go + r * 6 + 4) << 32)
                    for px in range(12):
                        img[r, px] = (v >> (4 * px)) & 15
                return img[:, :max(1, w)], ROM[o + 10]
    return None, 0
for code, nm in [(0x82A0, 'bracket_l'), (0x82A2, 'bracket_r')]:
    g, fl = glyph(code)
    if g is None:
        print('missing', hex(code)); continue
    rgba = np.zeros(g.shape + (4,), np.uint8)
    rgba[g != 0] = (255, 255, 255, 255)
    Image.fromarray(rgba).save(G + 'assets/ground/credits/%s.png' % nm)
    print(nm, g.shape, 'flags', fl); print('\n'.join(''.join('#' if v else '.' for v in row) for row in g))
print(len(pages), 'pages'); [print(p) for p in pages[:6]]
