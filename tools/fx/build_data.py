"""moves_data.json (Remixed waza_p.bin, vanilla for moves Remixed lacks) and learnsets.json (Remixed) -> tmp/eos/moveanim."""
import json, struct
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tables import MOVEANIM, T_EOS, common, _EOS, _RX
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'eos'))
from extract import strings
R=strings(_RX,'replace'); V=common.load_json(os.path.join(T_EOS,'strings_e.json'))
MB=8173; TB=13770; R_MON=18451
def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def decode_ints(d,o):
    out=[]
    while True:
        v=0
        while True:
            c=d[o]; o+=1; v=(v<<7)|(c&0x7f)
            if not c&0x80: break
        if v==0: break
        out.append(v)
    return out
TARGET={0:'enemies',1:'allies',2:'everyone',3:'user',4:'two_turn_move',5:'everyone_except_user',6:'allies_except_user',15:'special'}
RANGE={0:'front',1:'front_and_sides (3 tiles, like Wide Slash)',2:'around (8 tiles)',3:'room',4:'two_tiles_away (cuts corners)',5:'straight_line',6:'floor',7:'user',8:'front_cuts_corners',9:'two_tiles_cuts_corners',15:'special'}
COND={0:'none',1:'random_by_ai_condition1_chance',2:'hp_le_25pct',3:'has_negative_status',4:'asleep',5:'ghost_not_exposed',6:'hp_le_25pct_or_negative_status'}
CAT={0:'physical',1:'special',2:'status'}
def rng(v):
    t,r,c,u=v&15,(v>>4)&15,(v>>8)&15,(v>>12)&15
    return dict(raw=v,target=TARGET.get(t,'invalid_%d'%t),range=RANGE.get(r,'invalid_%d'%r),ai_condition=COND.get(c,'invalid_%d'%c),target_code=t,range_code=r,condition_code=c,unused=u,
                text=f"{TARGET.get(t,t)} / {RANGE.get(r,r)}")
def moves_of(path,S):
    d=open(path,'rb').read(); dp=struct.unpack_from('<I',d,4)[0]; mp,lp=struct.unpack_from('<II',d,dp)
    out=[]
    for i in range(559):
        e=d[mp+26*i:mp+26*i+26]
        out.append(dict(id=i,type=S[TB+e[2]] if e[2]<=19 else f'type_{e[2]}',type_id=e[2],category=CAT.get(e[3],e[3]),power=u16(e,0),
            accuracy1=e[11],accuracy2=e[10],pp=e[8],range=rng(u16(e,4)),ai_range=rng(u16(e,6)),hits=e[13],crit=e[15],max_ginseng=e[14],ai_weight=e[9],
            ai_condition1_chance=e[12],range_text_id=e[21],message_id=e[24],internal_move_id=u16(e,22),
            flags=dict(affected_by_magic_coat=bool(e[16]),snatchable=bool(e[17]),uses_mouth=bool(e[18]),ai_avoids_frozen_targets=bool(e[19]),usable_while_taunted=bool(e[20]))))
    return d,dp,lp,out
BAD={'$$$','[M:D1]','','NonRelearnable','??????????','Nothing'}
rd,rdp,rlp,rmoves=moves_of(os.path.join(_RX,'fs','BALANCE','waza_p.bin'),R)
vd,vdp,vlp,vmoves=moves_of(os.path.join(_EOS,'fs','BALANCE','waza_p.bin'),V)
data={}; rxn=set()
for m in rmoves:
    nm=R[MB+m['id']]
    if nm in BAD: continue
    m=dict(m,src='remixed'); key=nm if nm not in data else f"{nm} #{m['id']}"
    data[key]=m; rxn.add(nm)
for m in vmoves:
    nm=V[MB+m['id']]
    if nm in BAD or nm in rxn: continue
    data[nm]=dict(m,src='vanilla',note='Not in Explorers Remixed (by name); vanilla EoS data')
json.dump(data,open(common.p(os.path.join(MOVEANIM,'moves_data.json')),'w'),indent=1,ensure_ascii=False)
print('moves_data',len(data))
# learnsets
md=open(os.path.join(_RX,'fs','BALANCE','monster.md'),'rb').read(); cnt=struct.unpack_from('<I',md,4)[0]
ls={}; n=0
def mname(i): return R[MB+i] if 0<i<559 else f'move_{i}'
for i in range(cnt):
    o=rlp+12*i
    if o>=rdp: break
    pl,pt,pe=struct.unpack_from('<III',rd,o)
    if pl==0xAAAAAAAA: break
    lv=decode_ints(rd,pl) if pl else []
    lvl=[dict(move=mname(lv[k]),move_id=lv[k],level=lv[k+1]) for k in range(0,len(lv)-1,2)]
    tm=[mname(x) for x in (decode_ints(rd,pt) if pt else [])]
    egg=[mname(x) for x in (decode_ints(rd,pe) if pe else [])]
    if not (lvl or tm or egg): continue
    entid,unk,dex=struct.unpack_from('<HHH',md,8+68*i)
    gender=md[8+68*i+0x12]
    ls.setdefault(str(dex),[]).append(dict(md_index=i,entity_id=entid,name=R[R_MON+i] if R_MON+i<len(R) else None,gender=gender,level_up=lvl,tm_hm=tm,egg=egg))
    n+=1
json.dump(ls,open(os.path.join(MOVEANIM,'learnsets.json'),'w'),indent=1,ensure_ascii=False)
print('learnsets entries',n,'dex keys',len(ls))
