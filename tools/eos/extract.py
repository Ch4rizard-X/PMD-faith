#!/usr/bin/env python3
"""Explorers of Sky / Explorers Remixed intermediate files (into WORK_DIR/tmp/eos and tmp/eos_remix).

From the extracted vanilla ROM (common.EOS):
  eos/strings_e.json          every string of MESSAGE/text_e.str (cp1252; undefined bytes -> U+FFFD)
From the extracted Remixed ROM (common.REMIX):
  eos_remix/text_e.str, item_p.bin, item_s_p.bin, mappa_s.bin, monster.md   plain copies of the ROM files
  eos_remix/strings_e.json    every string of text_e.str (cp1252; undefined bytes kept as latin-1)
  eos_remix/items_all.json    all 1400 items: item_p.bin + names (string 6773+id) + descriptions (6773+3931+id)
  eos_remix/abilities.json    [name, description] per ability id, parsed from the descriptions (13913+id):
                              "[CS:E]Name[CR]: text"; Remixed's own abilities have no name string of their own
  eos_remix/remix_data.json   {"abilities": {id: [name, desc]} (all ids 0..255 that have one), "mons": [[md index, dex, ability1, ability2, name]]}
                              (monster.md: 2048 entries of 68 bytes; names at string 18451 + index)
The dungeon, fixed-room, tileset and move-animation intermediates are made by convert_dungeons.py,
fixed_rooms.py, tilesets.py and tools/fx/.
"""
import codecs
import json
import os
import re
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import EOS, REMIX, T_EOS, T_RX, rd, common  # noqa: E402

ITEM_NAME = 6773
ITEM_DESC = 6773 + 3931
ABIL_DESC = 13913
MON_NAME = 18451          # Remixed
N_ITEMS = 1400


def _latin1_fallback(e):
    return ''.join(chr(b) for b in e.object[e.start:e.end]), e.end


codecs.register_error('eos_latin1', _latin1_fallback)


def decode_str(data, errors='replace'):
    """MESSAGE/text_e.str: a table of u32 offsets (the first one also gives the count), NUL-terminated cp1252."""
    n = struct.unpack_from('<I', data, 0)[0] // 4
    out = []
    for o in struct.unpack_from('<%dI' % n, data, 0):
        e = data.find(b'\0', o)
        if e < 0:
            e = len(data)
        out.append(data[o:e].decode('cp1252', errors=errors))
    return out


def strings(base, errors='replace'):
    return decode_str(rd(base, 'fs', 'MESSAGE', 'text_e.str'), errors)


def clean(s):
    """Plain text of an in-game string: control tags [..] removed, whitespace collapsed."""
    return ' '.join(re.sub(r'\[[^\]]*\]', '', s).split())


def items_all(S, item_p):
    out = []
    for k in range(N_ITEMS):
        e = item_p[(k + 1) * 16:(k + 2) * 16]
        buy, sell, cat, spr, iid, move, rmin, rmax, pal, act, flags = struct.unpack_from('<HHBBHHBBBBB', e, 0)
        out.append({'id': k, 'name': clean(S[ITEM_NAME + k]), 'desc': clean(S[ITEM_DESC + k]), 'cat': cat, 'buy': buy, 'sell': sell,
                    'sprite': spr, 'pal': pal, 'move': move, 'rmin': rmin, 'rmax': rmax, 'act': act, 'flags': flags})
    return out


def ability_at(S, i):
    m = re.match(r'\[CS:E\](.*?)\[CR\]:?(.*)', S[ABIL_DESC + i], re.S)
    return [m.group(1), clean(m.group(2))] if m else None


def abilities(S):
    """The contiguous ability table (ids 0..140)."""
    out = []
    while ability_at(S, len(out)):
        out.append(ability_at(S, len(out)))
    return out


def abilities_all(S):
    """Every id 0..255 whose string slot holds an ability description (Remixed puts a few custom ones past the
    table, e.g. 155 Magic Bounce .. 176)."""
    return {str(i): ability_at(S, i) for i in range(256) if ability_at(S, i)}


def monsters(md, S):
    n = struct.unpack_from('<I', md, 4)[0]
    out = []
    for i in range(n):
        o = 8 + 68 * i
        dex = struct.unpack_from('<H', md, o + 4)[0]
        out.append([i, dex, md[o + 0x18], md[o + 0x19], S[MON_NAME + i]])
    return out


def dump(path, obj, **kw):
    with open(common.p(path), 'w', encoding='utf-8') as f:
        json.dump(obj, f, **kw)


def main():
    # vanilla strings
    V = strings(EOS, 'replace')
    dump(os.path.join(T_EOS, 'strings_e.json'), V)
    # Remixed: raw copies
    for src, dst in [(('fs', 'MESSAGE', 'text_e.str'), 'text_e.str'), (('fs', 'BALANCE', 'item_p.bin'), 'item_p.bin'),
                     (('fs', 'BALANCE', 'item_s_p.bin'), 'item_s_p.bin'), (('fs', 'BALANCE', 'mappa_s.bin'), 'mappa_s.bin'),
                     (('fs', 'BALANCE', 'monster.md'), 'monster.md')]:
        shutil.copyfile(os.path.join(REMIX, *src), common.p(os.path.join(T_RX, dst)))
    R = strings(REMIX, 'eos_latin1')
    dump(os.path.join(T_RX, 'strings_e.json'), R)
    dump(os.path.join(T_RX, 'items_all.json'), items_all(R, rd(REMIX, 'fs', 'BALANCE', 'item_p.bin')), ensure_ascii=False)
    ab = abilities(R)
    dump(os.path.join(T_RX, 'abilities.json'), ab, ensure_ascii=False, indent=0)
    mons = monsters(rd(REMIX, 'fs', 'BALANCE', 'monster.md'), R)
    dump(os.path.join(T_RX, 'remix_data.json'), {'abilities': abilities_all(R), 'mons': mons}, ensure_ascii=False)
    print('extract: %d vanilla / %d Remixed strings, %d items, %d abilities, %d monster.md entries'
          % (len(V), len(R), N_ITEMS, len(ab), len(mons)))


if __name__ == '__main__':
    main()
