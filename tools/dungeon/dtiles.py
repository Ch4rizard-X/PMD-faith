"""Red dungeon tilesets from the ROM (dungeon_map_access.c LoadDungeonTilesetAssets):
bNNfon (4bpp tiles), bNNcel (250 blocks x 3x3 tile entries), bNNpal (192 colours), bNNcanm (animated colours
160..191), bNNcex (auto-tiling table, 0x930 bytes) or bNNemap0 (arena picture, tilesets 64+).
fon/cel/cex are shared between tilesets through FON_MAP (gUnknown_8108EC0)."""
import struct
import numpy as np
import redrom as R

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
    pal = R.rgb_list(pal_o, 192)
    anim = []                                   # ReadAnimatedColorData: 32 x {duration, colours}
    canm = a.raw('b%02dcanm' % ts)
    for i in range(32):
        p = R.off(R.u32(canm + i * 4))
        cnt, dur = struct.unpack_from('<hh', R.rom(), p)
        anim.append({'dur': dur, 'colors': R.rgb_list(p + 4, cnt) if cnt > 0 else []})
    tiles = np.frombuffer(fon, np.uint8)
    nt = len(tiles) // 32
    t = tiles[:nt * 32].reshape(nt, 8, 4)
    px = np.empty((nt, 8, 8), np.uint8)
    px[:, :, 0::2] = t & 0xF
    px[:, :, 1::2] = t >> 4
    cells = np.frombuffer(cel[:250 * 18], '<u2').reshape(-1, 9)
    emap = cex = None
    if ts >= 64:
        emap = R.at_decompress(a.raw('b%02demap0' % ts))
    else:
        cex = R.at_decompress(a.raw('b%02dcex' % fn))
    return dict(px=px, cells=cells, pal=np.array(pal, np.uint8), anim=anim, emap=emap, cex=cex)


def rules(d):
    """The auto-tiling table as the game uses it: block = rules[variant + mask * 3] (784 masks x 3 variants)."""
    return list(d['cex'])


def render_block(d, b):
    """24x24 palette-index block (index % 16 == 0 -> transparent)."""
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
    """All blocks, 10 per row (240x600 for 250 blocks)."""
    idx = np.zeros((25 * 24, 10 * 24), np.int32)
    for b in range(min(nblocks, len(d['cells']))):
        idx[(b // 10) * 24:(b // 10) * 24 + 24, (b % 10) * 24:(b % 10) * 24 + 24] = render_block(d, b)
    return idx


def palette(d, anim_frame0=True):
    """192 colours; with anim_frame0 the animated slots (160..191) take the first colour of their animation
    (what the game shows on the first frame), else the placeholder colours stored in bNNpal."""
    pal = d['pal'].copy()
    if anim_frame0:
        for i, a in enumerate(d['anim']):
            if a['colors']:
                pal[160 + i] = a['colors'][0]
    return pal


def to_rgba(d, idx, opaque_zero=True, pal=None):
    pal = d['pal'] if pal is None else pal
    rgb = pal[np.clip(idx, 0, 191)]
    a = np.full(idx.shape, 255, np.uint8)
    out = np.dstack([rgb, a])
    if not opaque_zero:
        out[idx % 16 == 0] = 0
    return out
