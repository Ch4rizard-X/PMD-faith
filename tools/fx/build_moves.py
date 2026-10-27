"""moves.json (move name -> how to play its animation) -> tmp/eos/moveanim."""
import json, os
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tables import MOVEANIM, T_EOS, common, _EOS, _RX
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'eos'))
from extract import strings
from tables import vanilla, remixed, SHEETS
vM,vE,vS=vanilla(); rM,rE,rS=remixed()
V=common.load_json(os.path.join(T_EOS,'strings_e.json')); R=strings(_RX,'replace')
MOVE_BASE=8173; NMOVES=559
V_MON=8734; R_MON=18451
POINT={0:'head',1:'left_hand',2:'right_hand',3:'center',-1:'none'}
MON_ANIM=['Walk','Attack','Kick','Shoot','Strike','Sleep','Hurt','Idle','Swing','Double','Hop','Charge','Rotate']
def monanim(a):
    if a<len(MON_ANIM): return MON_ANIM[a]
    return {98:'SpinAllDirections(cw)',99:'SpinAllDirections(ccw)'}.get(a,'anim_%d'%a)
def px_per_frame(sp): return {1:2,2:3}.get(sp,6)
BAD={'$$$','[M:D1]','','NonRelearnable','??????????'}
ALT_V={'weather':{'sunny':543,'sandstorm':546,'rain':545,'hail':544,'snow':544},
       'charging':{8:547,60:548,75:549,100:550,151:551,153:552,156:553,205:554,348:555,477:560},
       'curse_ghost':556,'snore_awake':557,'sleeptalk_awake':558}
ALT_R={'weather':{'sunny':570,'sandstorm':574,'rain':573,'hail':571,'snow':571},
       'charging':{8:563,60:548,75:564,100:565,151:566,153:572,156:568,205:569,348:555,477:560},
       'curse_ghost':556,'snore_awake':557,'sleeptalk_awake':558}

def steps_for(m,E,move_id):
    a1,a2,a3,a4=m['anim']; out=[]
    def st(fx,role,where,attach,dirn):
        e=E[fx]
        w='screen' if e['type']==5 else where
        return dict(fx=fx,role=role,where=w,attach=attach if w!='screen' else 'screen',
                    direction=dirn if w!='screen' else None,blocking=not e['nonblock'],loop=bool(e['loop']),
                    sfx=None if e['sfx']<0 else e['sfx'],sheet=f'sheets/fx_{fx:04d}.png' if os.path.exists(os.path.join(SHEETS,f'fx_{fx:04d}.png')) else None)
    upt=POINT.get(m['point'],m['point'])
    if a1>0: out.append(st(a1,'charge','user',upt,'user_facing'))
    if a2>0:
        s=st(a2,'user','user',upt,'user_facing')
        if move_id==82: s['note']='played 8 times around the user (one per direction) -- hardcoded for move id 82'
        out.append(s)
    if a4>0: out.append(st(a4,'projectile','projectile',upt,'user_facing'))
    if a3>0: out.append(st(a3,'target','target',POINT.get(E[a3]['point'],E[a3]['point']),'down(0)'))
    return out
def where_of(steps):
    roles={s['role'] for s in steps}
    if any(s['where']=='screen' for s in steps) and not ({'projectile','target'}&{s['role'] for s in steps if s['where']!='screen'}): return 'screen'
    if 'projectile' in roles: return 'projectile'
    if 'target' in roles: return 'target'
    if roles: return 'user'
    return 'none'
def specials(m,S,monbase,names):
    out={}
    for k in range(m['spec_n']):
        s=S[m['spec_start']+k]
        nm=names[monbase+s['mon']] if monbase+s['mon']<len(names) else str(s['mon'])
        out.setdefault(nm,dict(monster_id=s['mon'],user_anim=s['mon_anim'],user_anim_name=monanim(s['mon_anim']),attach=POINT.get(s['point'],s['point']),sfx=None if s['sfx']==0x3F00 else s['sfx']))
    return out
def entry(mid,M,E,S,src,monbase,names,ALT):
    m=M[mid]; steps=steps_for(m,E,mid)
    d=dict(eos_move_id=mid,src=src,anim=[s['fx'] for s in steps],where=where_of(steps),
           speed=m['speed'],projectile_px_per_frame=px_per_frame(m['speed']) if m['anim'][3]>0 else None,
           sfx=None if m['sfx']==0x3F00 else m['sfx'],user_anim=m['mon_anim'],user_anim_name=monanim(m['mon_anim']),
           user_attach=POINT.get(m['point'],m['point']),steps=steps,
           flags=dict(raw=m['flags_raw'],low3=m['dir'],b3=m['flag8'],b4_no_wait_charge=m['flag10'],b5_idle_and_wait_before_attack=m['flag20'],b6_wait_all_after=m['flag40']))
    alt={}
    if mid==31:
        alt={f'weather_{k}':dict(move_anim_id=v,anim=[s['fx'] for s in steps_for(M[v],E,v)],steps=steps_for(M[v],E,v)) for k,v in ALT['weather'].items()}
    if mid in ALT['charging']:
        v=ALT['charging'][mid]; alt['charging_turn']=dict(move_anim_id=v,anim=[s['fx'] for s in steps_for(M[v],E,v)],steps=steps_for(M[v],E,v))
    for key,cond,mm in (('curse_ghost','user_is_ghost_type',237),('snore_awake','user_not_asleep',25),('sleeptalk_awake','user_not_asleep',227)):
        if mid==mm:
            v=ALT[key]; alt[cond]=dict(move_anim_id=v,anim=[s['fx'] for s in steps_for(M[v],E,v)],steps=steps_for(M[v],E,v))
    if mid==151:
        v=ALT['charging'][151]; alt['sunny_weather']=dict(move_anim_id=v,anim=[s['fx'] for s in steps_for(M[v],E,v)],steps=steps_for(M[v],E,v))
    if alt: d['alt']=alt
    sp=specials(m,S,monbase,names)
    if sp: d['per_species_overrides']=sp
    return d
moves={}; unresolved=[]
rx_names={}
for mid in range(1,NMOVES):
    nm=R[MOVE_BASE+mid]
    if nm in BAD: continue
    key=nm if nm not in moves else f'{nm} #{mid}'
    e=entry(mid,rM,rE,rS,'remixed',R_MON,R,ALT_R)
    vid=[i for i in range(1,NMOVES) if V[MOVE_BASE+i]==nm]
    if vid: e['vanilla_move_id']=vid[0]
    else: e['remixed_only']=True
    moves[key]=e; rx_names[nm]=mid
for mid in range(1,NMOVES):
    nm=V[MOVE_BASE+mid]
    if nm in BAD or nm in rx_names: continue
    e=entry(mid,vM,vE,vS,'vanilla',V_MON,V,ALT_V)
    e['note']='Not present (by name) in Explorers Remixed; vanilla EoS animation data.'
    moves[nm if nm not in moves else f'{nm} (vanilla)']=e
json.dump(moves,open(os.path.join(MOVEANIM,'moves.json'),'w'),indent=1,ensure_ascii=False)
print(len(moves),'moves;', sum(1 for v in moves.values() if v['src']=='vanilla'),'vanilla-only;',sum(1 for v in moves.values() if v.get('remixed_only')),'remixed-only')
