import sys, struct, importlib.util
import numpy as np
from PIL import Image
spec = importlib.util.spec_from_file_location("gwm", "/tmp/claude-0/pmd1/gen_world_map.py")
src = open("/tmp/claude-0/pmd1/gen_world_map.py").read().split("def build_map")[0]
ns = {"__file__": "/tmp/claude-0/pmd1/gen_world_map.py"}
exec(src, ns)
ROM = ns["ROM"]; at = ns["at_decompress"]
offs = [(0x384C9C, 0x388AD0), (0x388E50, 0x38CF98), (0x38D318, 0x391C48)]
for k, (bo, po) in enumerate(offs):
    d = at(ROM, bo)
    print(k, len(d))
    tm = [struct.unpack_from("<H", d, i*2)[0] for i in range(2048)]
    tiles = ns["tiles4"](d[0x1000:])
    idx = [e & 0x3FF for e in tm]
    print(" tiles", len(tiles), "idx", min(idx), max(idx), "pals", sorted(set(e >> 12 for e in tm)))
    pal = [(ROM[po+4*i], ROM[po+4*i+1], ROM[po+4*i+2], 255) for i in range(224)]
    out = np.zeros((160, 240, 4), np.uint8)
    for layer in (1, 0):   # BG3 (second half) below BG2
        m = [[tm[layer*1024 + y*32 + x] for x in range(32)] for y in range(32)]
        img = ns["render_bg"](m, tiles, pal, 30, 20, 0)
        msk = img[:, :, 3] > 0
        out[msk] = img[msk]
    Image.fromarray(out).save("titlen%d.png" % k)
