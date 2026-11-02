"""Downloads from GitHub without git (Python's standard library only), for builds that have no git: the APK's
on-phone build, or a computer without git. tools/fetch.py uses it when git isn't there (or MDR_NO_GIT=1).

  archive(owner, repo, dst, patterns)   one .tar.gz of the repository (codeload.github.com), streamed: only the
                                        files the patterns pick are written, the archive itself is never stored
  raw_files(owner, repo, dst, paths)    single files from raw.githubusercontent.com, many at once; files already
                                        there are kept, so a stopped download carries on where it was
  spritecollab_paths(tracker, patterns) the SpriteCollab files the patterns pick, listed from its tracker.json
                                        (its full archive is many GB; this fetches only what the game uses)
  git_sparse(url, dst, keep)            the files keep() picks from a repository's newest commit, through git's
                                        smart-HTTP protocol v2 (what SpriteCollab uses: raw.githubusercontent.com
                                        answers HTTP 429 after a few thousand single files)

Patterns are git sparse-checkout ones (no-cone): "/dir/" is a folder, "*" doesn't cross "/", [1-6] a range.
"""
import http.client
import json
import os
import re
import ssl
import sys
import tarfile
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = {"User-Agent": "md-recomp-build"}


def pattern_rx(p):
    s, i = "", 0
    while i < len(p):
        c = p[i]
        if c == "*":
            s += "[^/]*"
        elif c == "?":
            s += "[^/]"
        elif c == "[":
            j = p.index("]", i)
            s += p[i:j + 1]
            i = j
        else:
            s += re.escape(c)
        i += 1
    return re.compile("^" + s + ("" if p.endswith("/") else "$"))


def matcher(patterns):
    if not patterns:
        return lambda rel: True
    rxs = [pattern_rx(p if p.startswith("/") else "/" + p) for p in patterns]
    return lambda rel: any(r.match("/" + rel) for r in rxs)


class _Counter:
    def __init__(self, label):
        self.n, self.files, self.label, self.t0, self.last = 0, 0, label, time.time(), 0.0
        self.lock = threading.Lock()

    def add(self, nbytes, files=0):
        with self.lock:
            self.n += nbytes
            self.files += files
            now = time.time()
            if now - self.last > 5.0:
                self.last = now
                print(f"  {self.label}: {self.n / 1048576:.0f} MB, {self.files} files so far ({int(now - self.t0)} s)",
                      flush=True)


class _CountingReader:
    def __init__(self, f, counter):
        self.f, self.c = f, counter

    def read(self, n=-1):
        b = self.f.read(n)
        self.c.add(len(b))
        return b


def archive(owner, repo, dst, patterns=None, ref="HEAD", label=None):
    """Stream https://codeload.github.com/<owner>/<repo>/tar.gz/<ref> into dst, keeping what patterns pick."""
    keep = matcher(patterns)
    base = os.environ.get("MDR_CODELOAD_BASE", "https://codeload.github.com")      # (tests: a local server)
    url = f"{base}/{owner}/{repo}/tar.gz/{ref}"
    c = _Counter(label or repo)
    print(f"  downloading {url}", flush=True)
    req = urllib.request.Request(url, headers=UA)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                with tarfile.open(fileobj=_CountingReader(r, c), mode="r|gz") as t:
                    for m in t:
                        parts = m.name.split("/", 1)
                        if len(parts) < 2 or not parts[1]:
                            continue
                        rel = parts[1]
                        if not m.isfile() or not keep(rel):
                            continue
                        out = os.path.join(dst, *rel.split("/"))
                        os.makedirs(os.path.dirname(out), exist_ok=True)
                        with t.extractfile(m) as src, open(out + ".part", "wb") as f:
                            while True:
                                b = src.read(1 << 20)
                                if not b:
                                    break
                                f.write(b)
                        os.replace(out + ".part", out)
                        c.files += 1
            print(f"  {c.label}: {c.n / 1048576:.0f} MB downloaded, {c.files} files kept", flush=True)
            return c.files
        except (OSError, tarfile.TarError, http.client.HTTPException) as e:
            if attempt == 2:
                raise
            print(f"  {c.label}: download broke off ({e}), trying again", flush=True)
            time.sleep(5)


def raw_files(owner, repo, dst, paths, ref="master", workers=16, label=None):
    """Fetch raw.githubusercontent.com/<owner>/<repo>/<ref>/<path> for each path into dst (missing ones: skipped)."""
    todo = [p for p in paths if not os.path.isfile(os.path.join(dst, *p.split("/")))]
    c = _Counter(label or repo)
    c.files = len(paths) - len(todo)
    print(f"  {c.label}: {len(todo)} files to fetch ({len(paths) - len(todo)} already here)", flush=True)
    local = threading.local()
    ctx = ssl.create_default_context(cafile=os.environ.get("SSL_CERT_FILE") or None)
    missing = []
    host = "raw.githubusercontent.com"

    test_base = os.environ.get("MDR_RAW_BASE")          # (tests: a local http server)

    def conn():
        if getattr(local, "c", None) is None and test_base:
            pu = urllib.parse.urlparse(test_base)
            local.c = http.client.HTTPConnection(pu.hostname, pu.port, timeout=60)
        if getattr(local, "c", None) is None:
            proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
            if proxy:
                pu = urllib.parse.urlparse(proxy)
                local.c = http.client.HTTPSConnection(pu.hostname, pu.port or 443, timeout=60, context=ctx)
                local.c.set_tunnel(host, 443)
            else:
                local.c = http.client.HTTPSConnection(host, 443, timeout=60, context=ctx)
        return local.c

    def one(p):
        quoted = urllib.parse.quote(f"/{owner}/{repo}/{ref}/{p}")
        for attempt in range(4):
            try:
                cn = conn()
                cn.request("GET", quoted, headers=UA)
                r = cn.getresponse()
                body = r.read()
                if r.status == 404:
                    missing.append(p)
                    return
                if r.status != 200:
                    raise OSError(f"HTTP {r.status}")
                out = os.path.join(dst, *p.split("/"))
                os.makedirs(os.path.dirname(out), exist_ok=True)
                with open(out + ".part", "wb") as f:
                    f.write(body)
                os.replace(out + ".part", out)
                c.add(len(body), 1)
                return
            except (OSError, http.client.HTTPException):
                try:
                    local.c.close()
                except Exception:
                    pass
                local.c = None
                if attempt == 3:
                    raise
                time.sleep(2 * (attempt + 1))

    with ThreadPoolExecutor(workers) as ex:
        for _ in ex.map(one, todo):
            pass
    print(f"  {c.label}: {c.n / 1048576:.0f} MB fetched, {c.files} files ({len(missing)} not on the server)", flush=True)
    return missing


def spritecollab_paths(tracker, patterns):
    keep = matcher(patterns)
    out = set()

    def walk(node, parts):
        path = "/".join(parts)
        sf = node.get("sprite_files") or {}
        if sf:
            out.add(f"sprite/{path}/AnimData.xml")
            for a in sf:
                out.add(f"sprite/{path}/{a}-Anim.png")
        for e in node.get("portrait_files") or {}:
            out.add(f"portrait/{path}/{e}.png")
        for k, v in (node.get("subgroups") or {}).items():
            walk(v, parts + [k])

    for k, v in tracker.items():
        walk(v, [k])
    return sorted(p for p in out if keep(p))


# ------------------------------------------------------------------ git's own download protocol, without git
# raw.githubusercontent.com limits how many files one address may fetch (HTTP 429 after a few thousand), and
# SpriteCollab's full archive is many GB. git's smart HTTP protocol (version 2, the one `git clone --filter`
# uses) has neither problem: one request lists the newest commit's folders (no file contents), then the wanted
# files come in a few large batches. This speaks it with the standard library: pkt-lines over HTTPS, packfiles
# (zlib objects, delta-compressed ones rebuilt from their base).

def _pkt(s):
    b = s.encode() if isinstance(s, str) else s
    return b"%04x" % (len(b) + 4) + b


def _git_post(url, body, timeout=600):
    req = urllib.request.Request(url.rstrip("/") + "/git-upload-pack", data=body, method="POST", headers={
        "User-Agent": "git/2.47.0 (md-recomp)", "Git-Protocol": "version=2",
        "Content-Type": "application/x-git-upload-pack-request", "Accept": "application/x-git-upload-pack-result"})
    return urllib.request.urlopen(req, timeout=timeout)


def _pkt_lines(r):
    """Yield the payload of each pkt-line of a response (None for flush / delimiter packets)."""
    while True:
        h = r.read(4)
        if len(h) < 4:
            return
        n = int(h, 16)
        if n < 4:
            yield None
            continue
        d = b""
        while len(d) < n - 4:
            c = r.read(n - 4 - len(d))
            if not c:
                raise OSError("git response cut off")
            d += c
        yield d


def _git_head(url):
    body = _pkt("command=ls-refs\n") + _pkt("agent=git/2.47.0\n") + b"0001" + _pkt("symrefs\n") + _pkt("ref-prefix HEAD\n") + b"0000"
    with _git_post(url, body, 120) as r:
        for d in _pkt_lines(r):
            if d:
                oid = d.decode().split(" ", 1)[0]
                if len(oid) == 40:
                    return oid
    raise OSError("no HEAD in " + url)


def _git_fetch_pack(url, wants, extra=(), counter=None):
    """One protocol-v2 fetch; returns the packfile bytes."""
    body = _pkt("command=fetch\n") + _pkt("agent=git/2.47.0\n") + b"0001" + _pkt("no-progress\n") + _pkt("ofs-delta\n")
    for e in extra:
        body += _pkt(e + "\n")
    body += b"".join(_pkt("want %s\n" % w) for w in wants) + _pkt("done\n") + b"0000"
    pack = bytearray()
    with _git_post(url, body) as r:
        in_pack = False
        for d in _pkt_lines(r):
            if d is None:
                continue
            if not in_pack:
                if d.strip() == b"packfile":
                    in_pack = True
                continue
            band = d[0]
            if band == 1:
                pack += d[1:]
                if counter:
                    counter.add(len(d) - 1)
            elif band == 3:
                raise OSError("git server: " + d[1:].decode("utf-8", "replace").strip())
    return bytes(pack)


def _delta_apply(base, delta):
    def varint(i):
        v = shift = 0
        while True:
            c = delta[i]
            i += 1
            v |= (c & 0x7f) << shift
            shift += 7
            if not c & 0x80:
                return v, i
    _, i = varint(0)
    size, i = varint(i)
    out = bytearray()
    while i < len(delta):
        op = delta[i]
        i += 1
        if op & 0x80:
            off = ln = 0
            for k in range(4):
                if op & (1 << k):
                    off |= delta[i] << (8 * k)
                    i += 1
            for k in range(3):
                if op & (0x10 << k):
                    ln |= delta[i] << (8 * k)
                    i += 1
            out += base[off:off + (ln or 0x10000)]
        elif op:
            out += delta[i:i + op]
            i += op
        else:
            raise ValueError("bad delta")
    if len(out) != size:
        raise ValueError("delta size mismatch")
    return bytes(out)


def _pack_objects(pack, known=None):
    """{sha1 hex: (type, bytes)} of every object in a packfile (deltas rebuilt; bases may also be in known)."""
    import hashlib
    import zlib
    if pack[:4] != b"PACK":
        raise OSError("not a git packfile")
    count = int.from_bytes(pack[8:12], "big")
    q = 12
    by_off, objs = {}, {}
    names = {1: b"commit", 2: b"tree", 3: b"blob", 4: b"tag"}
    for _ in range(count):
        start = q
        c = pack[q]
        q += 1
        typ = (c >> 4) & 7
        while c & 0x80:
            c = pack[q]
            q += 1
        base = None
        if typ == 6:
            c = pack[q]
            q += 1
            off = c & 0x7f
            while c & 0x80:
                c = pack[q]
                q += 1
                off = ((off + 1) << 7) | (c & 0x7f)
            base = by_off[start - off]
        elif typ == 7:
            bid = pack[q:q + 20].hex()
            q += 20
            base = objs.get(bid) or (known or {}).get(bid)
            if base is None:
                raise OSError("delta base %s missing" % bid)
        z = zlib.decompressobj()
        data = z.decompress(pack[q:])
        q = len(pack) - len(z.unused_data)
        if base is not None:
            typ_name, data = base[0], _delta_apply(base[1], data)
        else:
            typ_name = names[typ]
        sha = hashlib.sha1(typ_name + b" %d\0" % len(data) + data).hexdigest()
        by_off[start] = objs[sha] = (typ_name, data)
    return objs


def _tree_files(objs, tree, prefix=""):
    """(path, blob sha) of every file under a tree."""
    data = objs[tree][1]
    i = 0
    while i < len(data):
        sp = data.index(b" ", i)
        nul = data.index(b"\0", sp)
        mode, name = data[i:sp], data[sp + 1:nul].decode("utf-8", "surrogateescape")
        sha = data[nul + 1:nul + 21].hex()
        i = nul + 21
        if mode == b"40000":
            yield from _tree_files(objs, sha, prefix + name + "/")
        elif mode != b"160000":
            yield prefix + name, sha


def git_sparse(url, dst, keep, label=None, batch=2500):
    """The files `keep(path)` picks from the newest commit of a GitHub repository, into dst. Files already there with
    the right contents are kept, so a stopped download carries on."""
    import hashlib
    c = _Counter(label or url.rstrip("/").split("/")[-1])
    head = _git_head(url)
    print(f"  {c.label}: listing the files of {head[:10]}", flush=True)
    objs = _pack_objects(_git_fetch_pack(url, [head], ["deepen 1", "filter blob:none"], c))
    tree = objs[head][1].split(b"\n", 1)[0].split()[1].decode()
    todo = []
    for path, sha in _tree_files(objs, tree):
        if not keep(path):
            continue
        out = os.path.join(dst, *path.split("/"))
        if os.path.isfile(out):
            b = open(out, "rb").read()
            if hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest() == sha:
                c.files += 1
                continue
        todo.append((path, sha))
    del objs
    print(f"  {c.label}: {len(todo)} files to fetch ({c.files} already here)", flush=True)
    for k in range(0, len(todo), batch):
        part = todo[k:k + batch]
        for attempt in range(4):
            try:
                got = _pack_objects(_git_fetch_pack(url, sorted({s for _, s in part}), (), c))
                break
            except (OSError, http.client.HTTPException, ValueError) as e:
                if attempt == 3:
                    raise
                print(f"  {c.label}: download broke off ({e}), trying again", flush=True)
                time.sleep(5 * (attempt + 1))
        for path, sha in part:
            if sha not in got:
                raise OSError(f"{path}: not in the server's answer")
            out = os.path.join(dst, *path.split("/"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out + ".part", "wb") as f:
                f.write(got[sha][1])
            os.replace(out + ".part", out)
            c.files += 1
        print(f"  {c.label}: {c.files} files, {c.n / 1048576:.0f} MB so far", flush=True)
    return c.files


def fetch_spritecollab(dst, patterns, ref="master"):
    """SpriteCollab's top files (tracker.json & co.), then the sprites and portraits the patterns pick from its
    tracker, all through git's download protocol (git_sparse)."""
    os.makedirs(dst, exist_ok=True)
    url = "https://github.com/PMDCollab/SpriteCollab.git"
    top = {p.lstrip("/") for p in patterns if "*" not in p and "[" not in p}
    git_sparse(url, dst, lambda path: path in top, label="SpriteCollab")
    tracker = json.load(open(os.path.join(dst, "tracker.json"), encoding="utf-8"))
    want = set(spritecollab_paths(tracker, patterns))
    git_sparse(url, dst, lambda path: path in want, label="SpriteCollab")

if __name__ == "__main__":
    print(len(spritecollab_paths(json.load(open(sys.argv[1])), sys.argv[2:])))
