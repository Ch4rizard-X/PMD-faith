import sys, struct, json, os
sys.path.insert(0, os.path.dirname(__file__))
from eoslib import *
from PIL import Image
import numpy as np
d = open('/tmp/claude-0/eos/fs/DUNGEON/dungeon.bin', 'rb').read(); E = pack_entries(d)
out = '/tmp/claude-0/eos/tiles'; os.makedirs(out, exist_ok=True)
meta = {}
for t in range(170):
    dma = unpx(E[170 + t][16:])
    dpc = unpx(E[340 + t]); dpci = unpx(E[510 + t]); dpl = E[680 + t]
    pal = np.zeros((16, 16, 3), np.uint8)
    for i in range(len(dpl) // 4):
        pal[i // 16, i % 16] = list(dpl[i * 4:i * 4 + 3])
    ntile = len(dpci) // 32
    tiles = np.zeros((max(ntile, 1), 8, 8), np.uint8)
    for k in range(ntile):
        b = np.frombuffer(dpci, np.uint8, 32, k * 32)
        px = np.empty(64, np.uint8); px[0::2] = b & 0xF; px[1::2] = b >> 4
        tiles[k] = px.reshape(8, 8)
    nch = len(dpc) // 18
    cols = 10
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
    Image.fromarray(img).save(f'{out}/s{t:03d}.png')
    rules = list(dma[:0x300 * 3])
    meta[f's{t:03d}'] = {'img': f's{t:03d}.png', 'cols': cols, 'rules': rules}
json.dump(meta, open('/tmp/claude-0/eos/tilesets_eos.json', 'w'))
print('done', len(meta))
