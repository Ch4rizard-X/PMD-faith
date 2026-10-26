import sys, os, struct, json, re, hashlib
sys.path.insert(0, os.path.dirname(__file__))
from eoslib import *
B = '/tmp/claude-0/eos'
S = json.load(open(f'{B}/strings_e.json'))
arm9 = open(f'{B}/arm9.bin', 'rb').read()
ov10 = open(f'{B}/overlay_0010.bin', 'rb').read()
OV10 = 0x22BCA80
GAME = '/tmp/claude-0/pmd1/game'
DB = json.load(open(f'{GAME}/data/dungeons.json'))
ITEMS = json.load(open(f'{GAME}/data/items.json'))
SPECIES = json.load(open(f'{GAME}/data/species.json'))

# --- monster.md: EoS index -> national dex
md = open(f'{B}/fs/BALANCE/monster.md', 'rb').read()
nmd = struct.unpack_from('<I', md, 4)[0]
NAT = [struct.unpack_from('<H', md, 8 + i * 0x44 + 4)[0] for i in range(nmd)]

# --- item_p.bin (SIR0): categories
ip = open(f'{B}/fs/BALANCE/item_p.bin', 'rb').read()
dp = struct.unpack_from('<I', ip, 4)[0]
ICAT = {}
po_ = struct.unpack_from("<I", ip, 8)[0]
for i in range((po_ - 16) // 16):
    e = ip[16 + i * 16: 32 + i * 16]
    ICAT[struct.unpack_from('<H', e, 6)[0]] = e[4]
def iname(i): return S[6773 + i]
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
NAME2KEY = {}
for k, v in ITEMS.items():
    NAME2KEY.setdefault(norm(str(v.get('name', k))), k)
ALIAS = {'reviverseed': 'reviver', 'pokemon': 'poke', 'poke': 'poke'}
def item_key(i):
    n = norm(iname(i))
    return NAME2KEY.get(n) or (ALIAS.get(n) if ALIAS.get(n) in ITEMS or ALIAS.get(n) == 'poke' else None)
CATNAME = {0: 'thrown_line', 1: 'thrown_arc', 2: 'berries_seeds_vitamins', 3: 'food_gummies', 4: 'held_items',
           5: 'tms_hms', 6: 'poke', 8: 'other', 9: 'orbs', 10: 'link_box'}
TRAP = {1: 'mud', 2: 'sticky', 3: 'grimy', 4: 'summon', 5: 'pitfall', 6: 'warp', 7: 'gust', 8: 'spin', 9: 'slumber',
        10: 'slow', 11: 'seal', 12: 'poison', 13: 'selfdestruct', 14: 'explosion', 15: 'ppzero', 16: 'chestnut',
        17: 'wonder', 18: 'pokemon', 19: 'spiked', 20: 'spiked', 21: 'poison'}

# --- mappa_s.bin
mp = open(f'{B}/fs/BALANCE/mappa_s.bin', 'rb').read()
hdr = struct.unpack_from('<I', mp, 4)[0]
dl, fl, il, ml, tl = struct.unpack_from('<5I', mp, hdr)
def u16(o): return struct.unpack_from('<H', mp, o)[0]
def u32(o): return struct.unpack_from('<I', mp, o)[0]
def floors_of(mi):
    p = u32(dl + 4 * mi) + 18
    out = []
    while mp[p:p + 18] != bytes(18) and p < dl:
        out.append(struct.unpack_from('<9H', mp, p)); p += 18
    return out
def monsters(idx):
    p = u32(ml + 4 * idx); out = []
    while u16(p + 6) != 0:
        lv = u16(p) // 512; w = u16(p + 2); w2 = u16(p + 4); mid = u16(p + 6)
        out.append((lv, w, w2, mid)); p += 8
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
def traps(idx):
    p = u32(tl + 4 * idx)
    return [u16(p + 2 * i) for i in range(25)]
def diff_cum(d):
    out = {}; prev = 0
    for k in sorted(d):
        v = d[k]
        if v == 0xFFFF: out[k] = 1; continue
        if v == 0: continue
        if v > prev: out[k] = v - prev; prev = v
    return out

item_tables = DB['item_tables']; trap_tables = DB['trap_tables']
it_index = {}; tr_index = {}
def add_item_table(idx, desc):
    if idx in it_index: return it_index[idx]
    cats, items = item_list(idx)
    cw = diff_cum(cats); iw = diff_cum(items)
    out = []
    for c, w in sorted(cw.items()):
        if c not in CATNAME: continue
        lst = []
        if c == 6:
            lst = [['poke', 10000]]
        else:
            for i, ww in iw.items():
                if ICAT.get(i) == c:
                    k = item_key(i)
                    if k: lst.append([k, ww])
        if lst: out.append({'cat': CATNAME[c], 'p': w, 'items': lst})
    item_tables.append({'desc': desc, 'cats': out}); it_index[idx] = len(item_tables) - 1
    return it_index[idx]
def add_trap_table(idx):
    if idx in tr_index: return tr_index[idx]
    w = traps(idx); prev = 0; t = {}
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
SKIP = {0, 105, 106} | set(range(165, 180))
seen = set(); out = {}; report = []
base_index = max(int(v.get('index', 0)) for v in DB['dungeons'].values()) + 1
for did in range(180):
    if did in SKIP: continue
    name = S[16564 + did]
    if name in seen or 'Dummy' in name: continue
    seen.add(name)
    nf, mi, sf, tot = arm9[0x9E3A0 + 4 * did: 0x9E3A0 + 4 * did + 4]
    allf = floors_of(mi)
    flist = allf[sf:sf + nf]
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
        props[18] = 0                       # EoS fixed rooms handled separately
        if props[0] in (8, 11) or props[0] > 10: props[0] = 0
        pk = {}
        for lv, w, w2, mid in monsters(f[1]):
            if mid >= nmd: continue
            nat = NAT[mid]
            key = '%04d' % nat
            if nat == 0 or key not in SPECIES: continue
            pk.setdefault((key, lv), [0])[0] += 0
            pk[(key, lv)].append(w)
        # spawn weights are cumulative in list order
        ent = monsters(f[1]); prev = 0; pkl = {}
        for lv, w, w2, mid in ent:
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
    key = 'eos_' + re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')
    out[key] = {'dir': key, 'name': name, 'index': base_index, 'floors': floors, 'up': bool(flags & 1),
                'recruit': bool(flags & 8), 'max_items': r[5], 'party': r[6], 'turn_limit': struct.unpack_from('<h', r, 8)[0],
                'eos': True, 'eos_id': did,
                'eos_level': (sorted(lv_first)[len(lv_first)//2] if lv_first else 1)}
    base_index += 1
    report.append((did, key, len(floors), out[key]['eos_level'], floors[0]['music'], sum(1 for x in floors if x['eos_fixed'])))
json.dump({'dungeons': out, 'item_tables': item_tables, 'trap_tables': trap_tables}, open(f'{B}/eos_dungeons.json', 'w'))
for x in report: print(x)
print(len(out), 'dungeons;', len(item_tables), 'item tables;', len(trap_tables), 'trap tables')
