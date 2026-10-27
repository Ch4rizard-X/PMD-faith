"""Where the Explorers of Sky / Explorers Remixed tools read and write (all derived from tools/common.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

EOS = common.EOS                                   # vanilla Explorers of Sky, extracted (arm9.bin, overlay_*.bin, fs/)
REMIX = common.REMIX                               # Explorers Remixed, extracted (same layout)
T_EOS = os.path.join(common.TMP, 'eos')            # intermediates from vanilla EoS
T_RX = os.path.join(common.TMP, 'eos_remix')       # intermediates from Remixed
MOVEANIM = os.path.join(T_EOS, 'moveanim')         # move-animation tables + effect sheets
SHEETS = os.path.join(MOVEANIM, 'sheets')
TILES = os.path.join(T_EOS, 'tiles')               # EoS dungeon tileset previews

OV10 = 0x22BCA80                                   # overlay 10 load address (NA)
OV29 = 0x22DC240                                   # overlay 29 load address (NA)


def rd(*parts):
    path = os.path.join(*parts)
    common.need(path, 'Explorers file')
    with open(path, 'rb') as f:
        return f.read()


def need_roms():
    common.need(os.path.join(EOS, 'arm9.bin'), 'extracted Explorers of Sky ROM (run tools/fetch.py)')
    common.need(os.path.join(REMIX, 'arm9.bin'), 'extracted Explorers Remixed ROM (run tools/fetch.py)')
