"""Render a Red dungeon tileset (bNNfon/cel/pal) to the 10-column block sheet used by the remake,
plus an index sheet (palette index per pixel)."""
import numpy as np, struct
import redrom as R
from PIL import Image

FON_MAP = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 16, 23, 24, 25, 20, 23, 28,
    29, 30, 31, 32, 33, 28, 35, 36, 37, 30, 39, 40, 41,
    42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54,
    55, 56, 45, 45, 59, 60, 48, 62, 63, 64, 65, 66, 67,
    68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79]

def load(ts):
    a = R.dungeon()
    fn = FON_MAP[ts]
    fon = R.at_decompress(a.raw('b%02dfon' % fn))
    cel = R.at_decompress(a.raw('b%02dcel' % fn))
    pal_o = a.raw('b%02dpal' % ts)
    pal = R.rgb_list(pal_o, 160)   # verified against the remake's r*.webp sheets (0 mismatching pixels)
    # animated colours 160..191
    anim = []
    canm = a.raw('b%02dcanm' % ts)
    for i in range(32):
        p = R.off(R.u32(canm + i * 4))
        cnt, dur = struct.unpack_from('<hh', R.rom(), p)
        cols = R.rgb_list(p + 4, cnt) if cnt > 0 else []
        anim.append({'dur': dur, 'colors': cols})
    pal += R.rgb_list(pal_o + 160 * 4, 32)
    tiles = np.frombuffer(fon, np.uint8)
    nt = len(tiles) // 32
    t = tiles[:nt * 32].reshape(nt, 8, 4)
    px = np.empty((nt, 8, 8), np.uint8)
    px[:, :, 0::2] = t & 0xF
    px[:, :, 1::2] = t >> 4
    cells = np.frombuffer(cel[:250 * 18], '<u2').reshape(-1, 9)
    emap = None
    if ts >= 64:
        emap = R.at_decompress(a.raw('b%02demap0' % ts))
    return dict(px=px, cells=cells, pal=np.array(pal, np.uint8), anim=anim, emap=emap)

def render_block(d, b):
    """24x24 palette-index block (0 = transparent colour index 0 in any row)."""
    out = np.zeros((24, 24), np.int32)
    for k in range(9):
        e = int(d['cells'][b][k])
        ti = e & 0x3FF; hf = (e >> 10) & 1; vf = (e >> 11) & 1; pr = e >> 12
        t = d['px'][ti] if ti < len(d['px']) else np.zeros((8, 8), np.uint8)
        if hf: t = t[:, ::-1]
        if vf: t = t[::-1, :]
        v = np.where(t == 0, 0, pr * 16 + t.astype(np.int32))
        out[(k // 3) * 8:(k // 3) * 8 + 8, (k % 3) * 8:(k % 3) * 8 + 8] = v
    return out

def sheet(d, nblocks=250):
    idx = np.zeros((25 * 24, 10 * 24), np.int32)
    for b in range(min(nblocks, len(d['cells']))):
        idx[(b // 10) * 24:(b // 10) * 24 + 24, (b % 10) * 24:(b % 10) * 24 + 24] = render_block(d, b)
    return idx

def to_rgba(d, idx, opaque_zero=True):
    rgb = d['pal'][np.clip(idx, 0, 191)]
    a = np.full(idx.shape, 255, np.uint8)
    if not opaque_zero:
        a[idx % 16 == 0] = 0
    return np.dstack([rgb, a])
