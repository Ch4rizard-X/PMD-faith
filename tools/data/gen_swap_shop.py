#!/usr/bin/env python3
"""Croagunk's Swap Shop recipes from Explorers Remixed (game/data/swap_shop.json).

Explorers of Sky has no recipe table: each exclusive item's description names the set that makes it
("Swap a Bulba-Claw and a Bulba-Fang for a Grass-Guard ...", "You can get a Leafy Tie ... by swapping: a
Bulba-Claw, a Bulba-Fang, and a Grass-Guard."). This reads Remixed's item names / descriptions
(WORK_DIR/tmp/eos_remix/items_all.json, category 15 = exclusive items) and keeps, for every 2- and 3-star item,
the other exclusive items its description names. 3-star items with no named set ("very lucky" legendary items)
come only from a swap of any five exclusive items.
Needs game/data/items.json (the remake's item ids, matched by name).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import common  # noqa: E402


def main():
    rx = common.load_json(os.path.join(common.TMP, 'eos_remix', 'items_all.json'))
    items = common.load_json(os.path.join(common.DATA, 'items.json'))
    by_name = {}
    for k, v in items.items():
        if v.get('kind') == 'exclusive':
            by_name.setdefault(v['name'], k)
    ex = [i for i in rx if i['cat'] == 15 and i['name'] in by_name]
    names = sorted({i['name'] for i in ex}, key=len, reverse=True)
    pat = re.compile('|'.join(re.escape(n) for n in names))
    recipes = {}
    for i in ex:
        me = by_name[i['name']]
        star = int(items[me].get('rarity', 1))
        if star < 2:
            continue
        found = []
        desc = i['desc']
        cut = [desc.find(w) for w in ('Swap ', 'swapping:', 'offer ') if desc.find(w) >= 0]
        if cut:
            desc = desc[min(cut):]                 # only the sentence naming the set
        for m in pat.finditer(desc):
            n = m.group(0)
            if n != i['name'] and by_name[n] not in found:
                found.append(by_name[n])
        want = 2 if star == 2 else 3
        if len(found) == want:
            recipes[me] = found
    out = {'_source': 'Explorers Remixed item descriptions (tools/data/gen_swap_shop.py)', 'fee': 150,
           'any_count': {'1': 2, '2': 3, '3': 5}, 'recipes': recipes}
    with open(common.p(common.DATA, 'swap_shop.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1)
    print('swap shop: %d recipes (%d two-star, %d three-star)' % (
        len(recipes), sum(1 for r in recipes.values() if len(r) == 2), sum(1 for r in recipes.values() if len(r) == 3)))


if __name__ == '__main__':
    main()
