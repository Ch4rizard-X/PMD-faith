#!/usr/bin/env python3
"""Item icon atlas: game/assets/ui/items.png (16x16 cells, 16 per row) + game/data/item_icons.json {item key: [x, y]}.
Icons are Red's item sprites (pmd-red data/dungeon/itempat.inc, 4bpp 2x2 tiles) in Red's item palettes
(graphics/ax/pal/N.pal), as each item's sprite/pal in items.json says; the prototype's own items use the sprites and
palettes in proto_tables.ICON_* . Layout as the prototype had it: its items in name order, then the other Red items,
one cell per sprite+palette combination."""
import json
import os
import re
import sys

from PIL import Image

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402
import proto_tables as T  # noqa: E402
import redsrc  # noqa: E402

COLS = 16


def sprites():
    txt = redsrc.read("data/dungeon/itempat.inc")
    seg = txt.split("itempat:")[1].split(".global itempat_table")[0]
    data = bytes(int(m.group(1), 16) for m in re.finditer(r"0x([0-9a-fA-F]{2})", seg))
    cnt = int.from_bytes(data[:4], "little")
    arr = data[4:]
    out = []
    for s in range(cnt // 4):
        im = [[0] * 16 for _ in range(16)]
        for t in range(4):
            tx, ty = (t % 2) * 8, (t // 2) * 8
            for y in range(8):
                for x in range(8):
                    b = arr[(s * 4 + t) * 32 + y * 4 + x // 2]
                    im[ty + y][tx + x] = (b >> 4) if x & 1 else b & 15
        out.append(im)
    return out


def palette(n):
    lines = redsrc.read("graphics/ax/pal/%d.pal" % n).split("\n")[3:19]
    return [tuple(map(int, ln.split())) + (255,) for ln in lines]


def main():
    items = common.load_json(os.path.join(common.DATA, "items.json"))
    proto_items = common.load_json(os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto_items.json"))
    SP = sprites()
    pals = {}

    def render(sprite, pal):
        if isinstance(pal, dict):
            cols = {int(i): tuple(int(c[j:j + 2], 16) for j in (1, 3, 5)) + (255,) for i, c in pal.items()}
        else:
            cols = pals.setdefault(pal, dict(enumerate(palette(pal))))
        im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        for y in range(16):
            for x in range(16):
                v = SP[sprite][y][x]
                if v:
                    im.putpixel((x, y), cols[v])
        return im

    def look(k):
        it = items.get(k, {})
        if "sprite" in it:
            return it["sprite"], it["pal"]
        for tab in (T.ICON_ROM, T.ICON_RECOLOUR, T.ICON_STANDIN):
            if k in tab:
                return tab[k]
        return None

    # the prototype's icons: its items (minus the Mega Stone, which had none) and Poke, in name order
    base = sorted((set(proto_items) - {"megastone"}) | {"poke"})
    cells, icons = {}, {}
    for n, k in enumerate(base):
        icons[k] = [(n % COLS) * 16, (n // COLS) * 16]
        if look(k):
            cells[tuple(icons[k])] = look(k)
    combo = {}
    for k, v in items.items():
        if "sprite" in v and k in icons:
            combo.setdefault((v["sprite"], v["pal"]), icons[k])
    used = set(tuple(v) for v in icons.values())
    free = [(x, y) for y in range(0, 512, 16) for x in range(0, COLS * 16, 16) if (x, y) not in used]
    for k, v in items.items():
        if "sprite" in v and k not in icons:
            c = (v["sprite"], v["pal"])
            if c not in combo:
                combo[c] = list(free.pop(0))
                cells[tuple(combo[c])] = c
            icons[k] = list(combo[c])
    h = max(y for _, y in cells) + 16
    atlas = Image.new("RGBA", (COLS * 16, h), (0, 0, 0, 0))
    for (x, y), (s, p) in cells.items():
        atlas.paste(render(s, p), (x, y))
    atlas.save(common.p(common.ASSETS, "ui", "items.png"))
    with open(common.p(common.DATA, "item_icons.json"), "w") as f:
        json.dump(icons, f, separators=(",", ":"))
    print("item icons", len(icons), "cells", len(cells), "atlas", atlas.size)


if __name__ == "__main__":
    main()
