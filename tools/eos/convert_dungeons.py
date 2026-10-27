#!/usr/bin/env python3
"""Explorers of Sky dungeons -> the game's dungeon format.

convert() reads one extracted ROM (vanilla or Remixed): the dungeon list in arm9 (floor counts, restrictions),
BALANCE/mappa_s.bin (floor layouts, spawn lists, item lists, trap lists), monster.md (EoS index -> national dex),
BALANCE/item_p.bin (item categories), text_e.str (names) and overlay 10 (music table), and returns
{'dungeons', 'item_tables', 'trap_tables'}: new item/trap tables are appended after the given base tables.

main() writes WORK_DIR/tmp/eos/eos_dungeons.json from vanilla EoS, using the Red part of game/data/dungeons.json
(Red's 64 dungeons and the item/trap tables they use) as the base, like the original conversion did.
"""
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import EOS, OV10, T_EOS, common, rd  # noqa: E402

CATNAME = {0: 'thrown_line', 1: 'thrown_arc', 2: 'berries_seeds_vitamins', 3: 'food_gummies', 4: 'held_items',
           5: 'tms_hms', 6: 'poke', 8: 'other', 9: 'orbs', 10: 'link_box'}
TRAP = {1: 'mud', 2: 'sticky', 3: 'grimy', 4: 'summon', 5: 'pitfall', 6: 'warp', 7: 'gust', 8: 'spin', 9: 'slumber',
        10: 'slow', 11: 'seal', 12: 'poison', 13: 'selfdestruct', 14: 'explosion', 15: 'ppzero', 16: 'chestnut',
        17: 'wonder', 18: 'pokemon', 19: 'spiked', 20: 'spiked', 21: 'poison'}
ALIAS = {'reviverseed': 'reviver', 'pokemon': 'poke', 'poke': 'poke'}
SKIP = {0, 105, 106} | set(range(165, 180))
DUNGEON_NAME = 16564
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())


def dungeon_key(name):
    return 'eos_' + re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')


def red_part(db):
    """The non-EoS dungeons of a dungeons.json and the item/trap tables they use (a prefix of the table lists)."""
    red = {k: v for k, v in db['dungeons'].items() if not k.startswith('eos_')}
    it = max([fl[x] for d in red.values() for fl in d['floors'] for x in ('items', 'shop', 'house_items', 'buried')] + [-1])
    tr = max([fl['traps'] for d in red.values() for fl in d['floors']] + [-1])
    return {'dungeons': red, 'item_tables': db['item_tables'][:it + 1], 'trap_tables': db['trap_tables'][:tr + 1]}


def convert(S, arm9, ov10, md, ip, mp, DB, ITEMS, SPECIES, catname=CATNAME):
    nmd = struct.unpack_from('<I', md, 4)[0]
    NAT = [struct.unpack_from('<H', md, 8 + i * 0x44 + 4)[0] for i in range(nmd)]
    ICAT = {}
    po_ = struct.unpack_from('<I', ip, 8)[0]
    for i in range((po_ - 16) // 16):
        e = ip[16 + i * 16: 32 + i * 16]
        ICAT[struct.unpack_from('<H', e, 6)[0]] = e[4]
    NAME2KEY = {}
    for k, v in ITEMS.items():
        NAME2KEY.setdefault(norm(str(v.get('name', k))), k)

    def item_key(i):
        n = norm(S[6773 + i])
        return NAME2KEY.get(n) or (ALIAS.get(n) if ALIAS.get(n) in ITEMS or ALIAS.get(n) == 'poke' else None)

    hdr = struct.unpack_from('<I', mp, 4)[0]
    dl, fl, il, ml, tl = struct.unpack_from('<5I', mp, hdr)
    u16 = lambda o: struct.unpack_from('<H', mp, o)[0]
    u32 = lambda o: struct.unpack_from('<I', mp, o)[0]

    def floors_of(mi):
        p = u32(dl + 4 * mi) + 18
        out = []
        while mp[p:p + 18] != bytes(18) and p < dl:
            out.append(struct.unpack_from('<9H', mp, p)); p += 18
        return out

    def monsters(idx):
        p = u32(ml + 4 * idx); out = []
        while u16(p + 6) != 0:
            out.append((u16(p) // 512, u16(p + 2), u16(p + 4), u16(p + 6))); p += 8
        return out

    def item_list(idx):
        p = u32(il + 4 * idx); cid = 0; cats = {}; items = {}; proc_cat = True
        while cid <= 363:
            v = u16(p); p += 2
            if v > 0x7530 and v != 0xFFFF:
                cid += v - 0x7530
            else:
                (cats if proc_cat else items)[cid] = v; cid += 1
            if cid >= 0xF and proc_cat:
                proc_cat = False; cid -= 0xF + 1
        return cats, items

    def diff_cum(d):
        out = {}; prev = 0
        for k in sorted(d):
            v = d[k]
            if v == 0xFFFF: out[k] = 1; continue
            if v == 0: continue
            if v > prev: out[k] = v - prev; prev = v
        return out

    item_tables = list(DB['item_tables']); trap_tables = list(DB['trap_tables'])
    it_index = {}; tr_index = {}

    def add_item_table(idx, desc):
        if idx in it_index: return it_index[idx]
        cats, items = item_list(idx)
        cw = diff_cum(cats); iw = diff_cum(items)
        out = []
        for c, w in sorted(cw.items()):
            if c not in catname: continue
            lst = []
            if c == 6:
                lst = [['poke', 10000]]
            else:
                for i, ww in iw.items():
                    if ICAT.get(i) == c:
                        k = item_key(i)
                        if k: lst.append([k, ww])
            if lst: out.append({'cat': catname[c], 'p': w, 'items': lst})
        item_tables.append({'desc': desc, 'cats': out}); it_index[idx] = len(item_tables) - 1
        return it_index[idx]

    def add_trap_table(idx):
        if idx in tr_index: return tr_index[idx]
        p = u32(tl + 4 * idx)
        w = [u16(p + 2 * i) for i in range(25)]
        prev = 0; t = {}
        for i, v in enumerate(w):
            if v > prev:
                if i in TRAP: t[TRAP[i]] = t.get(TRAP[i], 0) + v - prev
                prev = v
        if not t: t = {'wonder': 10000}
        trap_tables.append(t); tr_index[idx] = len(trap_tables) - 1
        return tr_index[idx]

    def music_id(i):
        v = struct.unpack_from('<H', ov10, 0x22C555C - OV10 + 2 * i)[0]
        if v & 0x8000:
            v = struct.unpack_from('<H', ov10, 0x22C51FC - OV10 + 8 * (v & 0x7FFF))[0]
        return v

    out = {}
    seen = set()
    base_index = max(int(v.get('index', 0)) for v in DB['dungeons'].values()) + 1
    for did in range(180):
        if did in SKIP:
            continue
        name = S[DUNGEON_NAME + did]
        if name in seen or 'Dummy' in name:
            continue
        seen.add(name)
        nf, mi, sf, tot = arm9[0x9E3A0 + 4 * did: 0x9E3A0 + 4 * did + 4]
        flist = floors_of(mi)[sf:sf + nf]
        r = arm9[0xA0C64 + 12 * did: 0xA0C64 + 12 * did + 12]
        flags = struct.unpack_from('<I', r, 0)[0]
        floors = []
        lv_first = []
        for fi, f in enumerate(flist):
            lay = mp[fl + 32 * f[0]: fl + 32 * f[0] + 32]
            props = list(lay[:28])
            tileset = props[2]
            music = music_id(props[3])
            eos_fixed = props[18]
            props[18] = 0                       # EoS fixed rooms are handled separately (data/eos_fixed.json)
            if props[0] in (8, 11) or props[0] > 10: props[0] = 0
            prev = 0; pkl = {}                  # spawn weights are cumulative in list order
            for lv, w, w2, mid in monsters(f[1]):
                if w > prev:
                    if mid < nmd and NAT[mid] and ('%04d' % NAT[mid]) in SPECIES:
                        k = ('%04d' % NAT[mid], lv); pkl[k] = pkl.get(k, 0) + (w - prev)
                    prev = w
            pkarr = [[k[0], k[1], v] for k, v in pkl.items()]
            if fi == 0: lv_first = [k[1] for k in pkl]
            floors.append({'props': props, 'pk': pkarr,
                           'items': add_item_table(f[3], f'{name} F{fi+1}'), 'traps': add_trap_table(f[2]),
                           'shop': add_item_table(f[4], f'{name} shop'), 'house_items': add_item_table(f[5], f'{name} house'),
                           'buried': add_item_table(f[6], f'{name} buried'),
                           'eos_tileset': tileset, 'music': 'eos_%04d' % music, 'eos_fixed': eos_fixed})
        if not floors: continue
        key = dungeon_key(name)
        out[key] = {'dir': key, 'name': name, 'index': base_index, 'floors': floors, 'up': bool(flags & 1),
                    'recruit': bool(flags & 8), 'max_items': r[5], 'party': r[6], 'turn_limit': struct.unpack_from('<h', r, 8)[0],
                    'eos': True, 'eos_id': did,
                    'eos_level': (sorted(lv_first)[len(lv_first) // 2] if lv_first else 1)}
        base_index += 1
    return {'dungeons': out, 'item_tables': item_tables, 'trap_tables': trap_tables}


def from_rom(base, S, DB, ITEMS, SPECIES, catname=CATNAME, ov10_base=None):
    """convert() on an extracted ROM folder; overlay 10 (music table) from ov10_base (default: the same ROM)."""
    return convert(S, rd(base, 'arm9.bin'), rd(ov10_base or base, 'overlay_0010.bin'), rd(base, 'fs', 'BALANCE', 'monster.md'),
                   rd(base, 'fs', 'BALANCE', 'item_p.bin'), rd(base, 'fs', 'BALANCE', 'mappa_s.bin'), DB, ITEMS, SPECIES, catname)


def main(db=None, items=None, species=None):
    db = db or common.load_json(os.path.join(common.DATA, 'dungeons.json'))
    items = items or common.load_json(os.path.join(common.DATA, 'items.json'))
    species = species or common.load_json(os.path.join(common.DATA, 'species.json'))
    items = {k: v for k, v in items.items() if not v.get('eos_added')}     # the stage-1 items (also on a rebuild)
    S = common.load_json(os.path.join(T_EOS, 'strings_e.json'))
    res = from_rom(EOS, S, red_part(db), items, species)
    with open(os.path.join(T_EOS, 'eos_dungeons.json'), 'w') as f:
        json.dump(res, f)
    print('vanilla EoS:', len(res['dungeons']), 'dungeons;', len(res['item_tables']), 'item tables;', len(res['trap_tables']), 'trap tables')
    return res


if __name__ == '__main__':
    main()
