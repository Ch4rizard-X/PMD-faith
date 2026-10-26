"""Red dungeon tilesets missing from assets/tiles (dojo mazes and a few special floors): r01/05/08/20/22/26/32/33.
1x block sheet (10 cols of 24px blocks, like the other r*.webp), xBRZ 3x HD sheet (hd_rNN.webp, same as the
arena / t14 HD sheets) and the auto-tile rules (bNNcex, 0x930 bytes) into data/tilesets.json."""
import sys, json, types
import numpy as np
sys.path.insert(0, '/tmp/claude-0/pmd1/tools_dungeon')
import redrom as R, dtiles as D
from PIL import Image
G = '/tmp/claude-0/pmd1/game/'
sys.modules.setdefault('_xbrz', types.SimpleNamespace(__file__='/tmp/claude-0/libxbrz.so'))
sys.path.insert(0, '/tmp/claude-0/x_xbrz.py')
import xbrz as X

def build(ts):
    d = D.load(ts)
    idx = D.sheet(d)
    rgba = D.to_rgba(d, idx, opaque_zero=False)
    rules = list(R.at_decompress(R.dungeon().raw('b%02dcex' % D.FON_MAP[ts])))
    return Image.fromarray(rgba.astype(np.uint8), 'RGBA'), rules

if __name__ == '__main__':
    check = '--check' in sys.argv
    TS = json.load(open(G + 'data/tilesets.json'))
    if check:
        for k in ['r00', 'r02', 'r40']:
            im, rules = build(int(k[1:]))
            ref = Image.open(G + 'assets/tiles/' + TS[k]['img']).convert('RGBA')
            a = np.array(im); b = np.array(ref)
            vis = b[..., 3] > 0
            print(k, 'rules equal', rules == TS[k]['rules'], 'rgb mismatches', int((np.abs(a[..., :3].astype(int) - b[..., :3]).sum(2)[vis] > 0).sum()),
                  'alpha mismatches', int((a[..., 3] != b[..., 3]).sum()))
        sys.exit()
    for ts in [1, 5, 8, 20, 22, 26, 32, 33]:
        k = 'r%02d' % ts
        im, rules = build(ts)
        im.save(G + 'assets/tiles/%s.webp' % k, lossless=True, quality=100)
        hd = X.scale_pillow(im, 3)
        hd.save(G + 'assets/tiles/hd_%s.webp' % k, lossless=True, quality=100)
        TS[k] = {'img': k + '.webp', 'rules': rules, 'cols': 10, 'hd': 'hd_%s.webp' % k}
        print(k, im.size, hd.size)
    json.dump(TS, open(G + 'data/tilesets.json', 'w'), separators=(',', ':'))
