#!/usr/bin/env python3
"""Explorers of Sky fixed rooms (boss arenas): vanilla BALANCE/fixed.bin + the entity/monster/stat tables in
overlays 29 and 10.

raw()  -> WORK_DIR/tmp/eos/eos_fixed.json   every fixed room: {w, h, music (fixed-room music index), mons, tiles}
          tiles = tile action per cell (row-major, < 16; entity cells read 0), mons = monsters placed in the room
          (species key, x, y, behaviour, level/HP/stats from the overlay 10 stat table)
game() -> game/data/eos_fixed.json          the rooms the EoS dungeons use that hold at least one enemy:
          {w, h, terrain (0 wall, 1 floor, 2 secondary terrain, 3 chasm), leader [x, y], attendants [[x, y]..],
           mons [{sp, x, y, level, hp, atk, spa, def_, spd, exp}], music 'eos_NNNN'}
          Monsters with behaviour 10 (story allies such as guests) are left out.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import EOS, OV10, OV29, T_EOS, common, rd  # noqa: E402

# fixed-room tile action (< 16) -> game terrain
TERRAIN = {0: 1, 1: 1, 2: 0, 3: 0, 4: 1, 5: 2, 10: 3, 11: 1, 12: 1, 15: 0}
LEADER = 4                       # tile action: where the leader starts
ATTENDANT_MON = 0                # entity whose monster entry has no species: a team member's starting spot


class Fixed:
    def __init__(self):
        self.fx = rd(EOS, 'fs', 'BALANCE', 'fixed.bin')
        self.ov29 = rd(EOS, 'overlay_0029.bin')
        self.ov10 = rd(EOS, 'overlay_0010.bin')
        md = rd(EOS, 'fs', 'BALANCE', 'monster.md')
        self.NAT = [struct.unpack_from('<H', md, 8 + i * 0x44 + 4)[0] for i in range(struct.unpack_from('<I', md, 4)[0])]
        hdr = struct.unpack_from('<I', self.fx, 4)[0]
        self.ptrs = []
        c = hdr
        while self.fx[c:c + 4] != b'\xaa\xaa\xaa\xaa' and c + 4 <= len(self.fx):
            self.ptrs.append(struct.unpack_from('<I', self.fx, c)[0]); c += 4

    def ent(self, i):
        return struct.unpack_from('<3I', self.ov29, 0x23502EC - OV29 + 12 * i)

    def mon_entry(self, addr):
        return struct.unpack_from('<HBB', self.ov29, addr - OV29)

    def stats(self, si):
        lv, hp, exp, atk, spa, df, spd = struct.unpack_from('<HHhBBBB', self.ov10, 0x22C5938 - OV10 + 12 * si)
        return dict(level=lv, hp=hp, exp=exp, atk=atk, spa=spa, def_=df, spd=spd)

    def music(self, fid):
        return struct.unpack_from('<H', self.ov10, 0x22C6C70 - OV10 + 12 * fid)[0]

    def music_id(self, i):
        v = struct.unpack_from('<H', self.ov10, 0x22C555C - OV10 + 2 * i)[0]
        if v & 0x8000:
            v = struct.unpack_from('<H', self.ov10, 0x22C51FC - OV10 + 8 * (v & 0x7FFF))[0]
        return v

    def acts(self, fid):
        p = self.ptrs[fid]
        if p == 0 or p >= len(self.fx):
            return None
        w, h, _ = struct.unpack_from('<3H', self.fx, p)
        if w == 0 or h == 0 or w > 64 or h > 64:
            return None
        acts = []; q = p + 6
        while len(acts) < w * h:
            v, rep = struct.unpack_from('<HH', self.fx, q); q += 4
            acts += [v & 0xFFF] * (rep + 1)
        return w, h, acts       # the last RLE run may go past w*h (kept, like the original dump)

    def room(self, fid):
        r = self.acts(fid)
        if not r:
            return None
        w, h, acts = r
        mons, tiles, attendants, leader = [], [], [], None
        for idx, a in enumerate(acts):
            x, y = idx % w, idx // w
            if a >= 16:
                e = a - 16
                if e < 269:
                    ip, mp_, tp = self.ent(e)
                    if mp_:
                        mid, si, beh = self.mon_entry(mp_)
                        if mid and mid < len(self.NAT) and self.NAT[mid]:
                            mons.append({'sp': '%04d' % self.NAT[mid], 'x': x, 'y': y, 'beh': beh, **self.stats(si)})
                        elif mid == ATTENDANT_MON:
                            attendants.append([x, y])
                tiles.append(0)  # floor under the entity
            else:
                if a == LEADER and leader is None:
                    leader = [x, y]
                tiles.append(a)
        return {'w': w, 'h': h, 'music': self.music(fid), 'mons': mons, 'tiles': tiles}, attendants, leader


def raw(F=None):
    F = F or Fixed()
    out = {}
    for fid in range(len(F.ptrs)):
        r = F.room(fid)
        if r:
            out[fid] = r[0]
    with open(common.p(os.path.join(T_EOS, 'eos_fixed.json')), 'w') as f:
        json.dump(out, f)
    print('fixed rooms:', len(F.ptrs), 'pointers,', len(out), 'rooms')
    return out


def game(dungeons, F=None, out_path=None):
    F = F or Fixed()
    used = sorted({fl['eos_fixed'] for d in dungeons['dungeons'].values() for fl in d['floors'] if fl.get('eos_fixed')})
    out = {}
    for fid in used:
        r = F.room(fid)
        if not r:
            continue
        room, attendants, leader = r
        w, h = room['w'], room['h']
        _, _, acts = F.acts(fid)
        mons = [{'sp': m['sp'], 'x': m['x'], 'y': m['y'], 'level': m['level'], 'hp': m['hp'], 'atk': m['atk'], 'spa': m['spa'],
                 'def_': m['def_'], 'spd': m['spd'], 'exp': m['exp']} for m in room['mons'] if m['beh'] != 10]
        if not mons:
            continue
        terrain = [1 if a >= 16 else TERRAIN.get(a, 1) for a in acts[:w * h]]
        out[str(fid)] = {'w': w, 'h': h, 'terrain': terrain, 'leader': leader, 'attendants': attendants, 'mons': mons,
                         'music': 'eos_%04d' % F.music_id(room['music'])}
    common.save_json(out_path or os.path.join(common.DATA, 'eos_fixed.json'), out)
    print('data/eos_fixed.json:', len(out), 'boss rooms')
    return out


def main():
    F = Fixed()
    raw(F)
    game(common.load_json(os.path.join(common.DATA, 'dungeons.json')), F)


if __name__ == '__main__':
    main()
