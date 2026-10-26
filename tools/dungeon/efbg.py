"""Render Red's efbg (BG effect) animations (weather) to frame strips, following graphics_memory.c sub_8009A7C."""
import struct, glob, json, re
import numpy as np
from PIL import Image
E = '/tmp/claude-0/pmdred_full/data/effects/'

def load_pal(e):
    L = open(E + 'efbg%s.pal' % e).read().split('\n')[3:]
    return [tuple(int(x) for x in l.split()) for l in L if l.strip()]

def frames(e):
    src = open('/tmp/claude-0/pmdred_full/src/data/effects/efbg%s.c' % e).read()
    hdrs = re.findall(r'const u16 (gUnknown_[0-9A-F]+)\[\] = \{\s*([-\d,\s]+)\};\s*const u16 \1_tilemap\[\] = INCBIN_U16\("data/effects/(efbg\d+_\d+)\.bin"\)', src)
    order = re.search(r'const u16 \*const gUnknown_[0-9A-F]+\[\] = \{([^}]*)\}', src).group(1)
    names = [x.strip() for x in order.split(',') if x.strip()]
    by = {h[0]: ([int(v) for v in h[1].replace('\n', ' ').split(',') if v.strip()], h[2]) for h in hdrs}
    return [by[n] for n in names]

def render(e):
    pal = load_pal(e)
    im = np.array(Image.open(E + 'efbg%s.png' % e))
    nt = im.shape[0] // 8
    tiles = im.reshape(nt, 8, 8) & 0xF
    out = []
    for hdr, binf in frames(e):
        d = open(E + binf + '.bin', 'rb').read()
        v = list(struct.unpack('<%dH' % (len(d) // 2), d))
        cx, cy = hdr[2], hdr[3]
        tm = np.zeros((20, 30), np.int32)
        k = 0; run = 0
        for i in range(cy):
            for j in range(cx):
                if run == 0:
                    cur = v[k]; k += 1
                    if not (cur & 0xF000):
                        run = cur & 0x3FF; cur = 0
                    r4 = cur
                else:
                    r4 = 0
                if run: run -= 1
                if i < 20 and j < 30:
                    tm[i, j] = r4
        img = np.zeros((160, 240, 4), np.uint8)
        for i in range(20):
            for j in range(30):
                t = tm[i, j]
                ti = (t & 0x3FF) - 120
                if t == 0 or ti <= 0 or ti >= nt:
                    continue
                px = tiles[ti]
                if t & 0x400: px = px[:, ::-1]
                if t & 0x800: px = px[::-1, :]
                pr = t >> 12
                for y in range(8):
                    for x in range(8):
                        c = px[y, x]
                        if c:
                            img[i * 8 + y, j * 8 + x] = (*pal[pr * 16 + c], 255)
        out.append(dict(img=img, dur=hdr[4], fade=hdr[5], speed=hdr[6] - 65536 if hdr[6] > 32767 else hdr[6]))
    return out
