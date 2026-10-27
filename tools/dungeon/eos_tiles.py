"""Explorers of Sky dungeon tilesets from DUNGEON/dungeon.bin (a SIR0-less "pack" file).
Entries (file-format research by the SkyTemple project, skytemple-files dungeon_data/*):
  170+t  DMA  auto-tiling table (AT4PX-compressed, 16-byte header skipped): 3 types x 256 masks x 3 variants
  340+t  DPC  chunks (24x24 = 3x3 tile entries, u16: tile | hflip<<10 | vflip<<11 | palette<<12), PKDPX/AT4PX
  510+t  DPCI 4bpp tiles, compressed
  680+t  DPL  palettes (RGBx, 16 colours per row)
Rendered like the old tools/eos/tilesets.py: 10 chunks per row, RGB, rules = the first 0x300*3 DMA bytes."""
import struct
import numpy as np

N_TILESETS = 170


def px_decompress(data, flags):
    out = bytearray(); i = 0; n = len(data)
    while i < n:
        ctrl = data[i]; i += 1
        for b in range(7, -1, -1):
            if i >= n: break
            if ctrl & (1 << b):
                out.append(data[i]); i += 1
            else:
                nx = data[i]; i += 1
                hi = (nx >> 4) & 0xF; lo = nx & 0xF
                if hi in flags:
                    idx = flags.index(hi)
                    if idx == 0:
                        v = (lo << 4) | lo; out += bytes([v, v])
                    else:
                        base = lo
                        if idx == 1: base = (base + 1) & 0xFF
                        elif idx == 5: base = (base - 1) & 0xFF
                        ns = [base] * 4
                        if 1 <= idx <= 4: ns[idx - 1] = (ns[idx - 1] - 1) & 0xFF
                        else: ns[idx - 5] = (ns[idx - 5] + 1) & 0xFF
                        out += bytes([((ns[0] << 4) | ns[1]) & 0xFF, ((ns[2] << 4) | ns[3]) & 0xFF])
                else:
                    off = (-0x1000 + (lo << 8)) | data[i]; i += 1
                    st = len(out) + off
                    for k in range(hi + 3):
                        out.append(out[st + k])
    return bytes(out)


def unpx(b):
    if b[:5] == b'AT4PX':
        flags = list(b[7:16]); size = struct.unpack_from('<H', b, 16)[0]
        return px_decompress(b[18:], flags)[:size]
    if b[:5] == b'PKDPX':
        flags = list(b[7:16]); size = struct.unpack_from('<I', b, 16)[0]
        return px_decompress(b[20:], flags)[:size]
    return b


def pack_entries(d):
    n = struct.unpack_from('<I', d, 4)[0]
    return [d[o:o + l] for o, l in (struct.unpack_from('<II', d, 8 + 8 * i) for i in range(n))]


def render(E, t, cols=10):
    """-> (RGB numpy image, rules list)"""
    dma = unpx(E[170 + t][16:])
    dpc = unpx(E[340 + t]); dpci = unpx(E[510 + t]); dpl = E[680 + t]
    pal = np.zeros((16, 16, 3), np.uint8)
    for i in range(min(256, len(dpl) // 4)):
        pal[i // 16, i % 16] = list(dpl[i * 4:i * 4 + 3])
    ntile = len(dpci) // 32
    tiles = np.zeros((max(ntile, 1), 8, 8), np.uint8)
    for k in range(ntile):
        b = np.frombuffer(dpci, np.uint8, 32, k * 32)
        px = np.empty(64, np.uint8); px[0::2] = b & 0xF; px[1::2] = b >> 4
        tiles[k] = px.reshape(8, 8)
    nch = len(dpc) // 18
    rows = (nch + cols - 1) // cols
    img = np.zeros((rows * 24, cols * 24, 3), np.uint8)
    for c in range(nch):
        cx, cy = (c % cols) * 24, (c // cols) * 24
        for j in range(9):
            v = struct.unpack_from('<H', dpc, c * 18 + j * 2)[0]
            ti, hf, vf, pi = v & 0x3FF, v & 0x400, v & 0x800, v >> 12
            tl = tiles[ti] if ti < ntile else np.zeros((8, 8), np.uint8)
            if hf: tl = tl[:, ::-1]
            if vf: tl = tl[::-1, :]
            img[cy + (j // 3) * 8: cy + (j // 3) * 8 + 8, cx + (j % 3) * 8: cx + (j % 3) * 8 + 8] = pal[pi][tl]
    return img, list(dma[:0x300 * 3])
