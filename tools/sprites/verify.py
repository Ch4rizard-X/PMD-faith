import json,os,random
import numpy as np
from PIL import Image
P=json.load(open('/tmp/claude-0/sprites_extra/patch.json')); S=json.load(open('/tmp/claude-0/pmd1/game/data/sprites.json'))
KM=json.load(open('/tmp/claude-0/sprites_extra/gen/keymap.json'))
SH='/tmp/claude-0/sprites_extra/sheets'; SP='/tmp/claude-0/pmd1/game/assets/sp'
bad=0; sizes={}; ok=0; clash=0
for k,an in P.items():
    for nm,e in an.items():
        if nm in S[k]['anims']: clash+=1
        p=f"{SH}/{e['s']}" if os.path.exists(f"{SH}/{e['s']}") else f"{SP}/{e['s']}"
        if not os.path.exists(p): print('missing',k,nm,e['s']); bad+=1; continue
        if p not in sizes:
            with Image.open(p) as im: sizes[p]=im.size
        W,H=sizes[p]
        if e['x']+e['w']*len(e['dur'])>W or e['y']+e['h']*e['rows']>H or max(W,H)>4096: print('oob',k,nm); bad+=1
random.seed(1)
samp=random.sample([(k,n) for k in P for n in P[k] if P[k][n]['s'].startswith('x')],300)
for k,nm in samp:
    e=P[k][nm]; src=f"/tmp/claude-0/scanim/{KM[k]}/{nm}-Anim.png"
    if not os.path.exists(src): continue  # alias
    a=np.asarray(Image.open(src).convert('RGBA')); b=np.asarray(Image.open(f"{SH}/{e['s']}").convert('RGBA'))
    fw=a.shape[1]//max(1,a.shape[1]//e['w']) if True else 0
    # compare last frame of last row (centre-aligned; handles trim)
    i=len(e['dur'])-1; r=e['rows']-1
    B=b[e['y']+r*e['h']:e['y']+(r+1)*e['h'], e['x']+i*e['w']:e['x']+(i+1)*e['w']]
    # source frame size from AnimData unknown here; locate by centre
    import xml.etree.ElementTree as ET
    for an in ET.parse(f"/tmp/claude-0/scanim/{KM[k]}/AnimData.xml").getroot().iter('Anim'):
        if an.findtext('Name')==nm: ofw=int(an.findtext('FrameWidth')); ofh=int(an.findtext('FrameHeight'))
    cx=(ofw-e['w'])//2; cy=(ofh-e['h'])//2
    A=a[r*ofh+cy:r*ofh+cy+e['h'], i*ofw+cx:i*ofw+cx+e['w']]
    A=A.copy(); A[A[...,3]==0]=0
    if np.array_equal(A,B): ok+=1
    else: print('pixel mismatch',k,nm); bad+=1
print('bad',bad,'pixel ok',ok,'clash',clash)
