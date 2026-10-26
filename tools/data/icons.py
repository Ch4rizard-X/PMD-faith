import json
from PIL import Image
r=open('/tmp/claude-0/pmdred_full/baserom.gba','rb').read()
# itempat raw bytes from inc
import re
data=bytearray()
txt=open('/tmp/claude-0/pmdred_full/data/dungeon/itempat.inc').read()
seg=txt.split('itempat:')[1].split('.global itempat_table')[0]
for m in re.finditer(r'0x([0-9a-f]{2})',seg): data.append(int(m.group(1),16))
cnt=int.from_bytes(data[0:4],'little'); arr=data[4:]
print('tiles',cnt, len(arr))
def sprite(s):
    im=[[0]*16 for _ in range(16)]
    for t in range(4):
        tx,ty=(t%2)*8,(t//2)*8
        for y in range(8):
            for x in range(8):
                b=arr[(s*4+t)*32+y*4+x//2]
                im[ty+y][tx+x]=(b>>4) if x&1 else b&15
    return im
items=json.load(open('/tmp/claude-0/pmd1/game/data/items.json'))
icons=json.load(open('/tmp/claude-0/pmd1/game/data/item_icons.json'))
png=Image.open('/tmp/claude-0/pmd1/game/assets/ui/items.png').convert('RGBA')
bad=[];ok=0;nos=0
pal_by={}
for k,it in items.items():
    if 'sprite' not in it or k not in icons: nos+=1; continue
    s=it['sprite']; x0,y0=icons[k][:2]
    sp=sprite(s)
    diff=0
    for y in range(16):
        for x in range(16):
            a=png.getpixel((x0+x,y0+y))[3]>0
            if a!=(sp[y][x]!=0): diff+=1
            if sp[y][x]: pal_by.setdefault((it.get('pal'),sp[y][x]),set()).add(png.getpixel((x0+x,y0+y))[:3])
    if diff>4: bad.append((k,s,diff))
    else: ok+=1
print('ok',ok,'bad',len(bad),'nosprite',nos)
print(bad[:40])
amb=[(k,v) for k,v in pal_by.items() if len(v)>1]
print('ambiguous pal entries',len(amb), amb[:5])

def loadpal(n):
    L=open('/tmp/claude-0/pmdred_full/graphics/ax/pal/%d.pal'%n).read().split('\n')[3:19]
    return [tuple(map(int,l.split()))+(255,) for l in L]
pals=[loadpal(i) for i in range(14)]
def render(s,p):
    im=Image.new('RGBA',(16,16),(0,0,0,0)); sp=sprite(s)
    for y in range(16):
        for x in range(16):
            if sp[y][x]: im.putpixel((x,y),pals[p][sp[y][x]])
    return im
keys=[k for k,it in items.items() if 'sprite' in it and k in icons]
cmp=Image.new('RGBA',(36*20, 18*((len(keys)+19)//20)),(40,40,80,255))
for i,k in enumerate(keys):
    it=items[k]; x0,y0=icons[k][:2]
    cx,cy=(i%20)*36,(i//20)*18
    cmp.paste(png.crop((x0,y0,x0+16,y0+16)),(cx,cy+1))
    r=render(it['sprite'],it['pal']); cmp.alpha_composite(r,(cx+17,cy+1))
cmp.resize((cmp.width*2,cmp.height*2),Image.NEAREST).save('cmp.png')
print(len(keys))
from collections import Counter
pos=Counter(tuple(v[:2]) for v in icons.values())
shared=[k for k in keys if pos[tuple(icons[k][:2])]>1]
print('shared cells', shared)
out=png.copy()
for k in keys:
    it=items[k]; x0,y0=icons[k][:2]
    out.paste(Image.new('RGBA',(16,16),(0,0,0,0)),(x0,y0))
    out.alpha_composite(render(it['sprite'],it['pal']),(x0,y0))
out.save('items_red.png')
used=set(tuple(v[:2]) for v in icons.values())
print('used cells',len(used))
# group missing items by (sprite,pal); reuse cells of identical sprite+pal
combo={}
for k in keys: combo.setdefault((items[k]['sprite'],items[k]['pal']),icons[k][:2])
missing=[k for k,v in items.items() if 'sprite' in v and k not in icons]
H=256
free=[(x,y) for y in range(0,512,16) for x in range(0,256,16) if (x,y) not in used]
new={}
for k in missing:
    c=(items[k]['sprite'],items[k]['pal'])
    if c not in combo:
        combo[c]=list(free.pop(0))
        H=max(H,combo[c][1]+16)
        new[c]=combo[c]
    icons[k]=list(combo[c])
print('new cells',len(new),'height',H)
big=Image.new('RGBA',(256,H),(0,0,0,0)); big.paste(out,(0,0))
for c,(x,y) in new.items(): big.alpha_composite(render(*c),(x,y))
big.save('items_red.png')
json.dump(icons,open('item_icons_red.json','w'),separators=(',',':'))
