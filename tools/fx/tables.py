"""Move-animation tables: vanilla overlay 10 and Remixed BALANCE/anim.bin (SkyTemple ExtractAnimData layout)."""
import struct, json
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'eos'))
from paths import EOS as _EOS, REMIX as _RX, MOVEANIM, SHEETS, T_EOS, T_RX, common  # noqa: E402
EOS=_EOS+os.sep; RX=_RX+os.sep
OV10=0x22BCA80
def mv(e):
    a=struct.unpack_from('<4h',e,0); fl=struct.unpack_from('<I',e,8)[0]
    return dict(anim=list(a),dir=fl&7,flag8=bool(fl&8),flag10=bool(fl&0x10),flag20=bool(fl&0x20),flag40=bool(fl&0x40),flags_raw=fl,
        speed=struct.unpack_from('<I',e,12)[0],mon_anim=e[16],point=struct.unpack_from('<b',e,17)[0],
        sfx=struct.unpack_from('<H',e,18)[0],spec_n=struct.unpack_from('<h',e,20)[0],spec_start=struct.unpack_from('<H',e,22)[0])
def ef(e):
    t,fi,pal,ai,se,u14=struct.unpack_from('<IIIIiI',e,0)
    return dict(type=t,file=fi,pal=pal,anim_idx=ai,sfx=se,u14=u14,screen=e[24],point=struct.unpack_from('<b',e,25)[0],nonblock=e[26],loop=e[27])
def sp(e):
    return dict(mon=struct.unpack_from('<H',e,0)[0],mon_anim=e[2],point=struct.unpack_from('<b',e,3)[0],sfx=struct.unpack_from('<H',e,4)[0])
def vanilla():
    d=open(EOS+'overlay_0010.bin','rb').read()
    M=[mv(d[0x22C9064-OV10+i*24:][:24]) for i in range(563)]
    E=[ef(d[0x22CC52C-OV10+i*28:][:28]) for i in range(700)]
    S=[sp(d[0x22D11BC-OV10+i*6:][:6]) for i in range(7422)]
    return M,E,S
def remixed():
    d=open(RX+'fs/BALANCE/anim.bin','rb').read()
    p=struct.unpack_from('<5I',d,0)
    M=[mv(d[x:x+24]) for x in range(p[2],p[3],24)]
    E=[ef(d[x:x+28]) for x in range(p[3],p[4],28)]
    S=[sp(d[x:x+6]) for x in range(p[4],len(d)-5,6)]
    return M,E,S
