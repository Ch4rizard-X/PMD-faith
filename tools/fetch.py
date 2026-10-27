"""Step 1 of the build: download the public resources and extract your ROMs.

  python tools/fetch.py

Needs git. Downloads go to WORK_DIR/ext (see tools/common.py); nothing is written outside WORK_DIR.
"""
import os
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (EXT, PMDRED, PMDSKY, SPRITECOLLAB, EOS, REMIX, RED_ROM, EOS_ROM, REMIX_ROM, need)

REPOS = {
    # folder: (url, sparse patterns or None for everything)
    "pmd-red": ("https://github.com/pret/pmd-red.git", None),
    "pmd-sky": ("https://github.com/pret/pmd-sky.git", ["/src/", "/include/", "/data/"]),
    "pokeapi": ("https://github.com/PokeAPI/pokeapi.git", ["/data/v2/csv/"]),
    "skytemple-files": ("https://github.com/SkyTemple/skytemple-files.git",
                        ["/skytemple_files/_resources/ppmdu_config/pmd2scriptdata.xml"]),
    # SpriteCollab: every default form + Mega/Primal forms + shiny Idle frames + portraits
    "SpriteCollab": ("https://github.com/PMDCollab/SpriteCollab.git",
                     ["/tracker.json", "/credit_names.txt", "/LICENSE.md",
                      "/sprite/*/*-Anim.png", "/sprite/*/AnimData.xml",
                      "/sprite/*/000[1-6]/*-Anim.png", "/sprite/*/000[1-6]/AnimData.xml",
                      "/sprite/*/0000/0001/Idle-Anim.png", "/sprite/*/000[1-6]/0001/*-Anim.png",
                      "/portrait/*/*.png", "/portrait/*/000[1-6]/*.png",
                      "/portrait/*/0000/0001/Normal.png"]),
}


def git(*args, cwd=None):
    print("  git", " ".join(args))
    subprocess.run(["git", *args], cwd=cwd, check=True)


def fetch_repo(name, url, sparse):
    dst = os.path.join(EXT, name)
    if os.path.isdir(os.path.join(dst, ".git")):
        print(f"{name}: already downloaded")
        return
    os.makedirs(EXT, exist_ok=True)
    if sparse:
        git("clone", "--depth", "1", "--filter=blob:none", "--sparse", url, dst)
        git("sparse-checkout", "set", "--no-cone", *sparse, cwd=dst)
    else:
        git("clone", "--depth", "1", url, dst)


def build_xbrz():
    """xBRZ scaler for the HD tiles/maps: use the pip package if present, else compile it from source."""
    try:
        import xbrz  # noqa: F401
        print("xbrz: pip package found")
        return
    except ImportError:
        pass
    from common import XBRZ_DIR, XBRZ_LIB
    if os.path.exists(XBRZ_LIB):
        print("xbrz: already built")
        return
    if not os.path.isdir(XBRZ_DIR):
        git("clone", "--depth", "1", "https://github.com/ioistired/xbrz.py.git", XBRZ_DIR)
    cxx = shutil.which("g++") or shutil.which("clang++")
    if not cxx:
        sys.exit("xbrz: install the pip package `xbrz.py` or a C++ compiler (g++/clang++).")
    import sysconfig
    subprocess.run([cxx, "-O3", "-std=gnu++17", "-shared", "-fPIC", "-Ilib", "-I" + sysconfig.get_paths()["include"],
                    "lib/xbrz.cpp", "-o", XBRZ_LIB], cwd=XBRZ_DIR, check=True)
    print("xbrz: built", XBRZ_LIB)


def extract_nds(rom, out):
    """Explorers of Sky US: arm9 and overlays are stored uncompressed; copy them and the file system."""
    if os.path.exists(os.path.join(out, "arm9.bin")):
        print(f"{out}: already extracted")
        return
    d = open(rom, "rb").read()
    os.makedirs(out, exist_ok=True)
    fnt_off, _, fat_off, _ = struct.unpack_from("<IIII", d, 0x40)
    arm9_off, _, _, arm9_sz = struct.unpack_from("<IIII", d, 0x20)
    ov9_off, ov9_sz = struct.unpack_from("<II", d, 0x50)
    open(os.path.join(out, "arm9.bin"), "wb").write(d[arm9_off:arm9_off + arm9_sz])

    def fat(i):
        s, e = struct.unpack_from("<II", d, fat_off + 8 * i)
        return d[s:e]

    for k in range(ov9_sz // 32):
        ovid, *_rest = struct.unpack_from("<8I", d, ov9_off + 32 * k)
        fid = _rest[5]
        open(os.path.join(out, f"overlay_{ovid:04d}.bin"), "wb").write(fat(fid))

    def walk(dir_id, path):
        off, first, _ = struct.unpack_from("<IHH", d, fnt_off + 8 * (dir_id & 0xFFF))
        q = fnt_off + off
        fid = first
        while True:
            t = d[q]
            q += 1
            if t == 0:
                break
            ln = t & 0x7F
            name = d[q:q + ln].decode("latin1")
            q += ln
            if t & 0x80:
                sub, = struct.unpack_from("<H", d, q)
                q += 2
                walk(sub, os.path.join(path, name))
            else:
                fp = os.path.join(out, "fs", path, name)
                os.makedirs(os.path.dirname(fp), exist_ok=True)
                open(fp, "wb").write(fat(fid))
                fid += 1

    walk(0xF000, "")
    print(f"extracted {rom} -> {out}")


def main():
    need(RED_ROM, "Red Rescue Team ROM (red_rom)")
    need(EOS_ROM, "Explorers of Sky ROM (eos_rom)")
    need(REMIX_ROM, "Explorers Remixed ROM (remix_rom)")
    for name, (url, sparse) in REPOS.items():
        fetch_repo(name, url, sparse)
    build_xbrz()
    shutil.copyfile(RED_ROM, os.path.join(PMDRED, "baserom.gba"))
    extract_nds(EOS_ROM, EOS)
    extract_nds(REMIX_ROM, REMIX)
    print("fetch: done")


if __name__ == "__main__":
    main()
