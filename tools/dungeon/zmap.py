import redrom as R, numpy as np
from PIL import Image
def load():
    a = R.dungeon(); o = a.raw('zmappat')
    t = R.off(R.u32(o)); pal = R.rgb_list(R.off(R.u32(o + 4)), 16)
    cells = {}
    for typ in range(192):
        for q in range(4):
            p = R.off(R.u32(t + (typ * 4 + q) * 4))
            w = [R.u32(p + i * 4) for i in range(16)]
            px = np.zeros((8, 8), np.int16) - 1
            for row in range(8):
                m, v = w[row * 2], w[row * 2 + 1]
                for x in range(8):
                    if ((m >> (4 * x)) & 0xF) == 0:
                        px[row, x] = (v >> (4 * x)) & 0xF
            cells[(typ, q)] = px
    return cells, pal
