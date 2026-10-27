"""Minimal TrueType writer for pixel fonts (standard library only).

Each glyph is a set of pixels; it is written as rectangle contours (runs merged vertically), all points on the
curve, so any TrueType rasteriser (Godot's FreeType included) draws exactly those pixels at the design size.
Tables: cmap (format 4, Unicode BMP + Windows), glyf, loca, head, hhea, hmtx, maxp, name, OS/2, post (v3).
"""
import struct
import time


def _rects(pixels):
    """pixels: set of (x, y) cells, y downwards -> list of (x0, y0, x1, y1) cell rectangles."""
    rows = {}
    for x, y in pixels:
        rows.setdefault(y, set()).add(x)
    runs = {}
    for y, xs in rows.items():
        xs = sorted(xs)
        r, s = [], xs[0]
        for a, b in zip(xs, xs[1:] + [None]):
            if b != a + 1:
                r.append((s, a + 1))
                s = b
        runs[y] = r
    out, open_ = [], {}
    for y in sorted(runs):
        nxt = {}
        for run in runs[y]:
            if run in open_ and open_[run][1] == y:
                y0 = open_[run][0]
            else:
                y0 = y
            nxt[run] = (y0, y + 1)
        for run, (y0, y1) in open_.items():
            if run not in nxt or nxt[run][0] != y0:
                out.append((run[0], y0, run[1], y1))
        open_ = nxt
    for run, (y0, y1) in open_.items():
        out.append((run[0], y0, run[1], y1))
    return out


def _glyph(pixels, unit, base_row):
    """Glyph record; pixel row r spans y = (base_row - r - 1)*unit .. (base_row - r)*unit."""
    if not pixels:
        return b"", (0, 0, 0, 0), 0, 0
    pts, ends = [], []
    for x0, r0, x1, r1 in _rects(pixels):
        ya, yb = (base_row - r1) * unit, (base_row - r0) * unit
        xa, xb = x0 * unit, x1 * unit
        pts += [(xa, ya), (xa, yb), (xb, yb), (xb, ya)]      # clockwise (y up)
        ends.append(len(pts) - 1)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    bbox = (min(xs), min(ys), max(xs), max(ys))
    d = struct.pack(">hhhhh", len(ends), *bbox)
    d += b"".join(struct.pack(">H", e) for e in ends) + struct.pack(">H", 0)
    d += bytes([1]) * len(pts)
    px = py = 0
    xb = yb = b""
    for x, y in pts:
        xb += struct.pack(">h", x - px)
        yb += struct.pack(">h", y - py)
        px, py = x, y
    d += xb + yb
    if len(d) % 2:
        d += b"\0"
    return d, bbox, len(pts), len(ends)


def _checksum(b):
    b += b"\0" * (-len(b) % 4)
    return sum(struct.unpack(">%dI" % (len(b) // 4), b)) & 0xFFFFFFFF


def _cmap4(mapping):
    """mapping: {codepoint (BMP): glyph id}"""
    cps = sorted(c for c in mapping if c < 0xFFFF)
    segs, i = [], 0
    while i < len(cps):
        j = i
        while j + 1 < len(cps) and cps[j + 1] == cps[j] + 1 and mapping[cps[j + 1]] == mapping[cps[j]] + 1:
            j += 1
        segs.append((cps[i], cps[j], (mapping[cps[i]] - cps[i]) & 0xFFFF))
        i = j + 1
    segs.append((0xFFFF, 0xFFFF, 1))
    n = len(segs)
    sr = 2 * (1 << (n.bit_length() - 1))
    body = struct.pack(">HHHH", 2 * n, sr, (sr // 2).bit_length() - 1, 2 * n - sr)
    body += b"".join(struct.pack(">H", e) for _, e, _ in segs) + b"\0\0"
    body += b"".join(struct.pack(">H", s) for s, _, _ in segs)
    body += b"".join(struct.pack(">H", d) for _, _, d in segs)
    body += b"\0\0" * n
    sub = struct.pack(">HHH", 4, 6 + len(body), 0) + body
    return struct.pack(">HH", 0, 2) + struct.pack(">HHI", 0, 3, 20) + struct.pack(">HHI", 3, 1, 20) + sub


def _name(family, style):
    recs, strs = [], b""
    for pid, eid, lid, enc in ((1, 0, 0, "mac_roman"), (3, 1, 0x409, "utf-16-be")):
        for nid, s in ((1, family), (2, style), (3, family + " " + style), (4, family), (6, family.replace(" ", "") + "-" + style)):
            b = s.encode(enc)
            recs.append((pid, eid, lid, nid, len(b), len(strs)))
            strs += b
    hdr = struct.pack(">HHH", 0, len(recs), 6 + 12 * len(recs))
    return hdr + b"".join(struct.pack(">HHHHHH", *r) for r in recs) + strs


def write_ttf(path, glyphs, upm, ascent, descent, base_row, unit, family="Pixel Font", style="Regular"):
    """glyphs: list of (codepoints list, advance in pixels, set of (x, y) pixels); glyph 0 = .notdef is added."""
    recs = [(b"", (0, 0, 0, 0), 0, 0)]
    adv = [unit * 4]
    cmap = {}
    for gid, (cps, a, pix) in enumerate(glyphs, 1):
        recs.append(_glyph(pix, unit, base_row))
        adv.append(a * unit)
        for c in cps:
            cmap[c] = gid
    glyf, loca = b"", [0]
    for r in recs:
        glyf += r[0]
        loca.append(len(glyf))
    long_loca = loca[-1] >= 0x20000
    loca_b = b"".join(struct.pack(">I" if long_loca else ">H", o if long_loca else o // 2) for o in loca)
    boxes = [r[1] for r in recs if r[0]]
    xmin = min(b[0] for b in boxes); ymin = min(b[1] for b in boxes)
    xmax = max(b[2] for b in boxes); ymax = max(b[3] for b in boxes)
    now = int(time.mktime((2024, 1, 1, 0, 0, 0, 0, 0, 0))) + 2082844800
    head = struct.pack(">HHIIIHHqqhhhhHHhhh", 1, 0, 0x00010000, 0, 0x5F0F3CF5, 0x000B, upm, now, now,
                       xmin, ymin, xmax, ymax, 0, 3, 2, 1 if long_loca else 0, 0)
    n = len(recs)
    hhea = struct.pack(">IhhhHhhhhhhhhhhhH", 0x00010000, ascent, -descent, 0, max(adv), 0, 0, xmax, 1, 0, 0,
                       0, 0, 0, 0, 0, n)
    hmtx = b"".join(struct.pack(">Hh", a, (r[1][0] if r[0] else 0)) for a, r in zip(adv, recs))
    maxp = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, n, max(r[2] for r in recs), max(r[3] for r in recs),
                       0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    cps = sorted(cmap)
    os2 = struct.pack(">HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHHII", 3, int(sum(adv) / len(adv)), 400, 5, 0,
                      upm // 5, upm // 5, 0, upm // 10, upm // 5, upm // 5, 0, upm // 3, upm // 20, upm // 4, 0,
                      b"\0" * 10, 1, 0, 0, 0, b"NONE", 0x40, cps[0], min(cps[-1], 0xFFFF), ascent, -descent, 0,
                      ascent, descent, 1, 0)
    os2 += struct.pack(">hhHHH", ascent // 2, ascent, 0, 32, 0)
    post = struct.pack(">IIhhIIIII", 0x00030000, 0, -unit, unit, 1, 0, 0, 0, 0)
    tables = {b"OS/2": os2, b"cmap": _cmap4(cmap), b"glyf": glyf, b"head": head, b"hhea": hhea, b"hmtx": hmtx,
              b"loca": loca_b, b"maxp": maxp, b"name": _name(family, style), b"post": post}
    tags = sorted(tables)
    nt = len(tags)
    sr = 16 * (1 << (nt.bit_length() - 1))
    out = struct.pack(">IHHHH", 0x00010000, nt, sr, (sr // 16).bit_length() - 1, nt * 16 - sr)
    off = 12 + 16 * nt
    dirs, data = b"", b""
    head_off = 0
    for t in tags:
        b = tables[t]
        if t == b"head":
            head_off = off
        dirs += struct.pack(">4sIII", t, _checksum(b), off, len(b))
        pad = b + b"\0" * (-len(b) % 4)
        data += pad
        off += len(pad)
    font = bytearray(out + dirs + data)
    adj = (0xB1B0AFBA - _checksum(bytes(font))) & 0xFFFFFFFF
    struct.pack_into(">I", font, head_off + 8, adj)
    with open(path, "wb") as f:
        f.write(font)
