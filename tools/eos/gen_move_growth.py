#!/usr/bin/env python3
"""Explorers Remixed's Move Growth table -> game/data/move_growth.json.

Remixed uses SkyTemple's "Move Growth" patch (the Gates to Infinity system): BALANCE/mgrowth.bin holds
150 bytes per move = 25 levels x 6 bytes {u16 Exp. to the next level, u16 power bonus, u8 PP bonus,
u8 accuracy bonus}; bonuses add up level by level. Damaging moves share one table, status moves have an
all-zero one. Each successful use of a move gives it 3 Exp. (the patch's default).

Output: {"table": [[exp, power, pp, acc] x 25], "moves": [Remixed names of the moves that grow]}.
Needs WORK_DIR/remix (tools/fetch.py) and WORK_DIR/tmp/eos_remix/strings_e.json (tools/eos/extract.py).
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import common  # noqa: E402

REC = 150
LEVELS = 25
MOVE_NAME = 8173          # Remixed strings_e.json: move names start after this index (move id 1 = 8174)


def main(mgrowth=None, strings=None, out=None):
    mgrowth = mgrowth or os.path.join(common.REMIX, 'fs', 'BALANCE', 'mgrowth.bin')
    strings = strings or os.path.join(common.TMP, 'eos_remix', 'strings_e.json')
    out = out or os.path.join(common.DATA, 'move_growth.json')
    common.need(mgrowth, 'BALANCE/mgrowth.bin from the Explorers Remixed ROM')
    d = open(mgrowth, 'rb').read()
    S = common.load_json(strings)
    S = S if isinstance(S, list) else list(S.values())
    table = None
    grow = []
    for mv in range(1, len(d) // REC):
        r = d[mv * REC:(mv + 1) * REC]
        if not any(r):
            continue
        rows = [list(struct.unpack_from('<HHBB', r, i * 6)) for i in range(LEVELS)]
        if table is None:
            table = rows
        grow.append(S[MOVE_NAME + mv])
    with open(out, 'w', encoding='utf-8') as f:
        json.dump({'table': table, 'moves': grow}, f, ensure_ascii=False, separators=(',', ':'))
    print('move growth: %d moves, %d levels' % (len(grow), len(table or [])))


if __name__ == '__main__':
    main(*sys.argv[1:4])
