"""Readers for the pret/pmd-red decompilation (common.PMDRED) and the user's Red ROM (common.RED_ROM).
Shared by the stage-1 data tools in tools/data/."""
import csv
import json
import os
import re
import struct
import sys

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402

D = common.PMDRED


def path(*parts):
    return os.path.join(D, *parts)


def read(rel):
    with open(path(rel), encoding="utf-8", errors="replace") as f:
        return f.read()


def load(rel):
    return common.load_json(path(rel))


norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())


def names_from_s(rel, prefix):
    """label -> string for `.string` tables (monster/move/item names)."""
    s = read(rel)
    out = {}
    for m in re.finditer(r"\n(" + prefix + r"\w+):\s*\n\.string \"([^\"\\]*)", s):
        v = m.group(2)
        out[m.group(1)] = "Poke" if v == "{POKE}" else re.sub(r"\{[^}]*\}", "", v).strip()
    return out


def consts(rel, prefix):
    out = {}
    for m in re.finditer(r"#define (" + prefix + r"\w+)\s+(0x[0-9A-Fa-f]+|\d+)", read(rel)):
        out.setdefault(m.group(1), int(m.group(2), 0))
    return out


# ---------------------------------------------------------------- the ROM (system archive, AT decompression)
_rom = None


def rom():
    global _rom
    if _rom is None:
        p = path("baserom.gba")
        if not os.path.exists(p):
            p = common.need(common.RED_ROM, "Red Rescue Team ROM (red_rom)")
        with open(p, "rb") as f:
            _rom = f.read()
    return _rom


def _u32(o):
    return struct.unpack_from("<I", rom(), o)[0]


def _cstr(o):
    r = rom()
    return r[o:r.index(b"\0", o)].decode("latin1")


class Archive:
    """A pksdir0 file archive in the ROM (OpenFileAndGetFileDataPtr)."""

    def __init__(self, addr):
        o = addr - 0x08000000
        assert rom()[o:o + 7] == b"pksdir0", "not a pksdir0 archive (wrong ROM?)"
        n = _u32(o + 8)
        t = _u32(o + 12) - 0x08000000
        self.files = {}
        for i in range(n):
            self.files[_cstr(_u32(t + i * 8) - 0x08000000)] = _u32(t + i * 8 + 4) - 0x08000000

    def raw(self, name):
        o = self.files[name]
        if rom()[o:o + 4] in (b"SIRO", b"SIR0"):
            return _u32(o + 4) - 0x08000000
        return o


SYSTEM_ARCHIVE = 0x08300500     # gSystemFileArchive (data/system_sbin.s)


def at_decompress(o):
    """AT3PX / AT4PX decompression (src/decompress_at.c)."""
    src = rom()
    assert src[o:o + 2] == b"AT", src[o:o + 5]
    clen = src[o + 5] | (src[o + 6] << 8)
    idx = 0x12 if src[o + 2:o + 4] == b"4P" else 0x10
    if src[o + 4] == ord("N"):
        return bytes(src[o + 7:o + 7 + clen])
    flags = [src[o + 7 + i] + 3 for i in range(9)]
    dst = bytearray()
    cur = idx
    cmd_bit = 8
    byte = 0

    def put(a, b):
        dst.append(((a & 0xF) << 4) | (b & 0xF))
    while cur < clen:
        if cmd_bit == 8:
            byte = src[o + cur]
            cur += 1
            cmd_bit = 0
        if byte & 0x80 == 0:
            b = src[o + cur]
            command = (b >> 4) + 3
            tmp = (b & 0xF) << 8
            for k, f in enumerate(flags):
                if command == f:
                    command = 0x1F - k
            c = b & 0xF
            pairs = {0x1F: ((c, c), (c, c)), 0x1E: ((c, c + 1), (c + 1, c + 1)), 0x1D: ((c, c - 1), (c, c)),
                     0x1C: ((c, c), (c - 1, c)), 0x1B: ((c, c), (c, c - 1)), 0x1A: ((c, c - 1), (c - 1, c - 1)),
                     0x19: ((c, c + 1), (c, c)), 0x18: ((c, c), (c + 1, c)), 0x17: ((c, c), (c, c + 1))}
            if command in pairs:
                cur += 1
                for a, bb in pairs[command]:
                    put(a, bb)
            else:
                tmp += src[o + cur + 1]
                cur += 2
                tmp += len(dst) - 0x1000
                for _ in range(command):
                    dst.append(dst[tmp])
                    tmp += 1
        else:
            dst.append(src[o + cur])
            cur += 1
        cmd_bit += 1
        byte = (byte << 1) & 0xFF
    return bytes(dst)


_levels = {}


def level_table(mon_id):
    """Red's lvmp%03d file (GetLvlUpEntry): 100 x (total exp, hp, atk, spa, def, spd gains) for levels 1..100."""
    if mon_id not in _levels:
        arc = Archive(SYSTEM_ARCHIVE)
        d = at_decompress(arc.raw("lvmp%03d" % mon_id))
        rows = []
        for lv in range(100):
            exp, hp, atk, spa, df, spd, _ = struct.unpack_from("<iHBBBBH", d, lv * 12)
            rows.append((exp, hp, atk, spa, df, spd))
        _levels[mon_id] = rows
    return _levels[mon_id]


# ---------------------------------------------------------------- Red monster id -> national dex key
def red_mon_map():
    """{red monster index: '%04d' national dex} (same mapping as tools/ground/gen_ground_extra.py red_mon)."""
    by_name = {}
    with open(os.path.join(common.POKEAPI_CSV, "pokemon_species_names.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["local_language_id"] == "9" and int(row["pokemon_species_id"]) < 1000:
                by_name.setdefault(norm(row["name"]), "%04d" % int(row["pokemon_species_id"]))
    t = read("data/monster/monster_names.s")
    mnames = {}
    for m in re.finditer(r"\n(MonsterName\w+):\s*\n\.string \"([^\"\\]*)", t):
        mnames[m.group(1)] = re.sub(r"\{[^}]*\}", "", m.group(2)).strip()
    out = {}
    for i, d in enumerate(load("data/monster/monster_data.json")):
        nm = mnames.get(d["name"], "")
        k = by_name.get(norm(nm))
        if not k:
            low = norm(nm)
            for base in ["unown", "castform", "deoxys", "rayquaza"]:
                if low.startswith(base):
                    k = by_name.get(base)
        if k:
            out[i] = k
    return out
