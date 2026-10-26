import sys, os, struct, json
B = '/tmp/claude-0/eos'
fx = open(f'{B}/fs/BALANCE/fixed.bin', 'rb').read()
ov29 = open(f'{B}/overlay_0029.bin', 'rb').read(); O29 = 0x22DC240
ov10 = open(f'{B}/overlay_0010.bin', 'rb').read(); O10 = 0x22BCA80
md = open(f'{B}/fs/BALANCE/monster.md', 'rb').read()
NAT = [struct.unpack_from('<H', md, 8 + i * 0x44 + 4)[0] for i in range(struct.unpack_from('<I', md, 4)[0])]
hdr = struct.unpack_from('<I', fx, 4)[0]
# header points to list of floor pointers
ptrs = []
c = struct.unpack_from('<I', fx, hdr)[0] if False else hdr
while fx[c:c + 4] != b'\xaa\xaa\xaa\xaa' and c + 4 <= len(fx):
    ptrs.append(struct.unpack_from('<I', fx, c)[0]); c += 4
def ent(i):
    o = 0x23502EC - O29 + 12 * i
    return struct.unpack_from('<3I', ov29, o)
def mon_entry(addr):
    o = addr - O29
    mid, si, beh = struct.unpack_from('<HBB', ov29, o)
    return mid, si, beh
def stats(si):
    o = 0x22C5938 - O10 + 12 * si
    lv, hp, exp, atk, spa, df, spd = struct.unpack_from('<HHhBBBB', ov10, o)
    return dict(level=lv, hp=hp, exp=exp, atk=atk, spa=spa, def_=df, spd=spd)
def props(fid):
    o = 0x22C6C70 - O10 + 12 * fid
    return struct.unpack_from('<H', ov10, o)[0]
out = {}
for fid, p in enumerate(ptrs):
    if p == 0 or p >= len(fx): continue
    w, h, _ = struct.unpack_from('<3H', fx, p)
    if w == 0 or h == 0 or w > 64 or h > 64: continue
    acts = []; q = p + 6
    while len(acts) < w * h:
        v, rep = struct.unpack_from('<HH', fx, q); q += 4
        acts += [v & 0xFFF] * (rep + 1)
    mons = []
    tiles = []
    for idx, a in enumerate(acts):
        x, y = idx % w, idx // w
        if a >= 16:
            e = a - 16
            if e < 269:
                ip, mp_, tp = ent(e)
                if mp_:
                    mid, si, beh = mon_entry(mp_)
                    if mid and mid < len(NAT) and NAT[mid]:
                        s = stats(si)
                        mons.append({'sp': '%04d' % NAT[mid], 'x': x, 'y': y, 'beh': beh, **s})
            tiles.append(0)  # floor under entity
        else:
            tiles.append(a)
    out[fid] = {'w': w, 'h': h, 'music': props(fid), 'mons': mons, 'tiles': tiles}
json.dump(out, open(f'{B}/eos_fixed.json', 'w'))
print(len(ptrs), len(out))
E = json.load(open(f'{B}/eos_dungeons.json'))
used = sorted({f['eos_fixed'] for d in E['dungeons'].values() for f in d['floors'] if f['eos_fixed']})
for fid in used:
    r = out.get(fid) or out.get(str(fid))
    if not r: print(fid, 'missing'); continue
    bosses = [(m['sp'], m['level'], m['hp'], m['beh']) for m in r['mons']]
    print(fid, r['w'], r['h'], 'music', r['music'], bosses[:6])
