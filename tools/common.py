"""Shared paths for every build tool.

Settings come from build_config.json in the repository root (copy build_config.example.json) or from
environment variables of the same name in upper case (RED_ROM, EOS_ROM, REMIX_ROM, WORK_DIR).

  RED_ROM    your own Red Rescue Team (GBA, US) ROM
  EOS_ROM    your own Explorers of Sky (NDS, US) ROM
  REMIX_ROM  your own Explorers Remixed ROM (patched Explorers of Sky)
  WORK_DIR   where downloads and extracted files go (default: build_work/ in the repository)

Layout under WORK_DIR (made by tools/fetch.py):
  ext/pmd-red          pret/pmd-red decompilation (your RED_ROM copied in as baserom.gba)
  ext/pmd-sky          pret/pmd-sky decompilation (sources only)
  ext/SpriteCollab     PMDCollab/SpriteCollab (sprites, portraits, tracker.json)
  ext/pokeapi          PokeAPI CSV data
  ext/skytemple-files  SkyTemple's pmd2 script data XML
  eos/                 Explorers of Sky ROM extracted (arm9.bin, overlay_*.bin, fs/...)
  remix/               Explorers Remixed ROM extracted (same layout)
  tmp/                 intermediate files of the tools
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_cfg = {}
_cfg_path = os.path.join(ROOT, "build_config.json")
if os.path.exists(_cfg_path):
    with open(_cfg_path, encoding="utf-8") as f:
        _cfg = json.load(f)


def setting(name, default=None):
    v = os.environ.get(name.upper()) or _cfg.get(name) or default
    if isinstance(v, str) and v and not os.path.isabs(v):
        v = os.path.join(ROOT, v)
    return v


RED_ROM = setting("red_rom")
EOS_ROM = setting("eos_rom")
REMIX_ROM = setting("remix_rom")
WORK = setting("work_dir", "build_work")
# Red only: no Explorers of Sky ROMs given. The Explorers of Sky / Remixed parts of the build are skipped and the
# game gets only Red Rescue Team's content (data/build_info.json tells it).
RED_ONLY = not (EOS_ROM and REMIX_ROM)

EXT = os.path.join(WORK, "ext")
PMDRED = os.path.join(EXT, "pmd-red")
PMDSKY = os.path.join(EXT, "pmd-sky")
SPRITECOLLAB = os.path.join(EXT, "SpriteCollab")
POKEAPI_CSV = os.path.join(EXT, "pokeapi", "data", "v2", "csv")
SKYTEMPLE_XML = os.path.join(EXT, "skytemple-files", "skytemple_files", "_resources", "ppmdu_config", "pmd2scriptdata.xml")
EOS = os.path.join(WORK, "eos")          # vanilla Explorers of Sky, extracted
REMIX = os.path.join(WORK, "remix")      # Explorers Remixed, extracted
TMP = os.path.join(WORK, "tmp")

GAME = os.path.join(ROOT, "game")
DATA = os.path.join(GAME, "data")
ASSETS = os.path.join(GAME, "assets")

for _d in (WORK, TMP, DATA, ASSETS):
    os.makedirs(_d, exist_ok=True)


def p(*parts):
    """Join and make the parent folder exist (for output files)."""
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def need(path, what):
    if not path or not os.path.exists(path):
        sys.exit(f"Missing {what}: {path or '(not set)'}. Run tools/fetch.py first, or check build_config.json.")
    return path


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, obj, pretty=False):
    with open(p(path), "w", encoding="utf-8") as f:
        if pretty:
            json.dump(obj, f, ensure_ascii=False, indent=1)
        else:
            json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))


XBRZ_DIR = os.path.join(EXT, "xbrz.py")
XBRZ_LIB = os.path.join(XBRZ_DIR, "libxbrz.so" if os.name != "nt" else "xbrz.dll")
_xbrz = None


def xbrz_module():
    """The xBRZ pixel-art scaler: the pip package `xbrz.py` if installed, else the copy tools/fetch.py
    downloaded and compiled into WORK_DIR/ext/xbrz.py."""
    global _xbrz
    if _xbrz is None:
        try:
            import xbrz as m
        except ImportError:
            import types
            need(XBRZ_LIB, "compiled xBRZ library")
            sys.modules.setdefault("_xbrz", types.SimpleNamespace(__file__=XBRZ_LIB))
            sys.path.insert(0, XBRZ_DIR)
            import xbrz as m
        _xbrz = m
    return _xbrz


def xbrz_scale(img, factor):
    """xBRZ upscaling of a Pillow image (factor 2..6)."""
    return xbrz_module().scale_pillow(img.convert("RGBA"), factor)
