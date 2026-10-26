#!/usr/bin/env python3
"""Export the walkable-town data of the old HTML remake into the Godot project.

Reads TOWN_MAPS / TOWN_GRIDS / TOWN_OPEN / TOWN_BLOCKS / BASE_SHAPE / MAPFILES straight out of the old
index.html (evaluated with node), bakes the walk grids (traced grid + TOWN_OPEN patches, Cubone's base =
intersection of the other bases, as gridFor/baseInterGrid did), precomputes the animated map layers
(packs/anim/*.json) into steady per-frame tile states, copies the map art (HD webp when it exists) into
res://assets/town/ and writes res://data/town.json.
"""
import base64, json, os, re, shutil, subprocess, sys

OLD = "/tmp/claude-0/rt/app/src/main/assets/www"
GAME = "/tmp/claude-0/pmd1/game"
HTML = open(os.path.join(OLD, "index.html"), encoding="utf-8").read()


def js_literal(name):
    """Text of `const NAME = {...}` (balanced braces, strings skipped)."""
    m = re.search(r"\bconst %s\s*=\s*" % re.escape(name), HTML)
    if not m:
        sys.exit("missing " + name)
    i = m.end()
    assert HTML[i] == "{", name
    depth, j, q = 0, i, None
    while True:
        c = HTML[j]
        if q:
            if c == "\\":
                j += 1
            elif c == q:
                q = None
        elif c in "'\"`":
            q = c
        elif c == "/" and HTML[j + 1] == "/":
            j = HTML.index("\n", j)
            continue
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return HTML[i:j + 1]
        j += 1


def js_eval(names):
    src = "const out = {};\n"
    for n in names:
        src += "out[%r] = (%s);\n" % (n, js_literal(n))
    src += "process.stdout.write(JSON.stringify(out));\n"
    r = subprocess.run(["node", "-e", src], capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


D = js_eval(["TOWN_MAPS", "TOWN_GRIDS", "TOWN_OPEN", "TOWN_BLOCKS", "BASE_SHAPE", "MAPFILES"])
TM, TG, TOPEN, TBLK, SHAPE, MAPFILES = (D[k] for k in ["TOWN_MAPS", "TOWN_GRIDS", "TOWN_OPEN", "TOWN_BLOCKS", "BASE_SHAPE", "MAPFILES"])

# old map key -> Godot map key (= the exit id the town emits)
KEYMAP = {"square": "square", "post": "post_office", "dojo": "dojo", "pond": "whiscash", "base": "base"}
# old action -> interact id
ACTS = {"shop": "kecleon_shop", "wares": "kecleon_wares", "bank": "persian_bank", "storage": "kangaskhan_storage",
        "link": "gulpin_shop", "wiggly": "wigglytuff", "dojo": "makuhita_dojo", "post": "pelipper_board",
        "board": "pelipper_board", "whiscash": "whiscash", "base": "bed", "mailbox": "mailbox", "nohome": "nohome"}
# exits that start something instead of changing town map
EXIT_ACTS = {("dojo", "dungeon"): "dojo_maze", ("base", "dungeon"): "world_map", ("base", "friendwalk"): "friend_areas"}
# Which song plays where (music.js, checked against pmd-red's song table)
MUSIC = {"square": "007", "post_office": "007", "whiscash": "007", "base": "001", "dojo": "110"}
MUSIC_FILES = {"001": "001 Rescue Team Base.mp3", "007": "007 Pokemon Square.mp3", "110": "110 Makuhita Dojo.mp3",
               "017": "017 Kecleon Shop.mp3"}


def grid_for(key):
    if key in TG:
        g = TG[key]
        bits = bytearray(base64.b64decode(g["b64"]))
    else:   # base_0066: walkable on every other base map
        ks = [k for k in TG if k.startswith("base_")]
        g = TG[ks[0]]
        B = [base64.b64decode(TG[k]["b64"]) for k in ks]
        bits = bytearray(255 for _ in B[0])
        for b in B:
            for i in range(len(bits)):
                bits[i] &= b[i]
    C, W, H = g["C"], g["W"], g["H"]
    for x0, y0, x1, y1 in TOPEN.get(key, []):
        for gy in range(y0 // C, -(-y1 // C)):
            for gx in range(x0 // C, -(-x1 // C)):
                i = gy * W + gx
                bits[i >> 3] |= 1 << (i & 7)
    return {"C": C, "W": W, "H": H, "b64": base64.b64encode(bytes(bits)).decode()}


def anim_for(file):
    jp = os.path.join(OLD, "assets/packs/anim/%s.json" % file)
    if not os.path.exists(jp):
        return None
    j = json.load(open(jp))
    d = j["d"]
    if not d:
        return None
    # each frame lists the 8x8 tiles that change [pos, atlas index, ...]; Town replays them on top of
    # the picture (the steady state of frame f = one full lap of changes + the changes of frames 0..f-1)
    hd = os.path.exists(os.path.join(OLD, "assets/hd/packs/anim/%s.webp" % file))
    return {"t": j["t"], "tw": j["tw"], "per": j["per"], "dur": j["dur"], "d": d,
            "atlas": "anim_%s.%s" % (file, "webp" if hd else "png"), "k": 3 if hd else 1}


out_dir = os.path.join(GAME, "assets/town")
os.makedirs(out_dir, exist_ok=True)


def copy(src, dst_name):
    dst = os.path.join(out_dir, dst_name)
    if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src):
        shutil.copy2(src, dst)


def image_entry(file):
    """Copy a map picture (HD webp preferred) and its animated layer; return the json entry."""
    from PIL import Image
    png = os.path.join(OLD, "assets/maps/%s.png" % file)
    w, h = Image.open(png).size
    hdp = os.path.join(OLD, "assets/hd/maps/%s.webp" % file)
    e = {"w": w, "h": h}
    if os.path.exists(hdp):
        copy(hdp, file + ".webp")
        e["tex"] = file + ".webp"
        e["k"] = Image.open(hdp).size[0] // w
    else:
        copy(png, file + ".png")
        e["tex"] = file + ".png"
        e["k"] = 1
    a = anim_for(file)
    if a:
        src = os.path.join(OLD, "assets/hd/packs/anim/%s.webp" % file) if a["k"] == 3 else os.path.join(OLD, "assets/packs/anim/%s.png" % file)
        copy(src, a["atlas"])
        e["anim"] = a
    return e


def act_id(a):
    return ACTS.get(a, a)


maps = {}
for ok, M in TM.items():
    key = KEYMAP[ok]
    m = {"music": MUSIC.get(key, "007"), "spawn": [M["spawn"]["x"], M["spawn"]["y"], M["spawn"]["f"]],
         "npcs": [{"id": act_id(n["act"]), "sp": n["sp"], "x": n["x"], "y": n["y"], "f": 0, "reach": n["reach"]} for n in M["npcs"]],
         "spots": [{"id": act_id(s["act"]), "reach": s["reach"]} for s in M["spots"]],
         "blocks": [[b["x"], b["y"], b["r"]] for b in M.get("blocks", [])],
         "exits": [], "arrive": {}}
    for ex in M["exits"]:
        if "to" in ex:
            m["exits"].append({"r": ex["r"], "to": KEYMAP[ex["to"]]})
        else:
            m["exits"].append({"r": ex["r"], "to": EXIT_ACTS[(ok, ex["act"])], "back": ex["back"]})
    if key != "base":
        m.update(image_entry(MAPFILES[ok]))
        m["grid"] = grid_for(ok)
        m["xblocks"] = []
    maps[key] = m

# arrival points: where you appear on map B when you come from map A (the exit's sx, sy, f)
for ok, M in TM.items():
    for ex in M["exits"]:
        if "to" in ex:
            maps[KEYMAP[ex["to"]]]["arrive"][KEYMAP[ok]] = [ex["sx"], ex["sy"], ex["f"]]
# exits to other maps put you back at the arrival point from that map if the switch doesn't happen
for key, m in maps.items():
    for ex in m["exits"]:
        if "back" not in ex and ex["to"] in m["arrive"]:
            ex["back"] = m["arrive"][ex["to"]]

# team bases: one picture/grid per house shape
bases = {}
for mk, file in MAPFILES.items():
    if not mk.startswith("base_"):
        continue
    shape = mk[5:]
    e = image_entry(file)
    e["grid"] = grid_for(mk)
    e["xblocks"] = [[b["x"], b["y"], b["r"]] for b in TBLK.get(mk, [])]
    bases[shape] = e

copy(os.path.join(OLD, "assets/packs/flags.png"), "flags.png")

data = {"maps": maps, "bases": bases, "base_shape": SHAPE, "follow_gap": 30, "speed": 84,
        "flag": {"tex": "flags.png", "x": 198, "y": 116, "w": 32, "h": 32, "frames": 6, "ms": 140}}
with open(os.path.join(GAME, "data/town.json"), "w") as f:
    json.dump(data, f, separators=(",", ":"))

mdir = os.path.join(GAME, "assets/music")
for mid, fn in MUSIC_FILES.items():
    src = os.path.join(OLD, "assets/music", fn)
    if os.path.exists(src) and not os.path.exists(os.path.join(mdir, mid + ".mp3")):
        shutil.copy2(src, os.path.join(mdir, mid + ".mp3"))

print("maps:", ", ".join(maps), "| bases:", ", ".join(bases), "| town.json", os.path.getsize(os.path.join(GAME, "data/town.json")), "bytes")
