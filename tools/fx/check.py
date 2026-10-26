"""Render contact sheets purely from moves.json + sheets/*.json/png (validates the deliverable format)."""
import json, sys
from PIL import Image, ImageDraw
ROOT='/tmp/claude-0/eos/moveanim/'
moves=json.load(open(ROOT+'moves.json'))
def frames_of(fx,dirn):
    meta=json.load(open(f'{ROOT}sheets/fx_{fx:04d}.json')); sheet=Image.open(ROOT+'sheets/'+meta['image'])
    anims=meta['animations']; key=str(dirn) if str(dirn) in anims else '0'
    return meta,[(f,sheet.crop((f['x'],f['y'],f['x']+f['w'],f['y']+f['h'])) if f['w'] else None) for f in anims[key]]
def strip(fx,dirn,maxf=16):
    meta,fr=frames_of(fx,dirn)
    if meta['kind']=='screen':
        cells=[]
        step=max(1,len(fr)//maxf)
        for f,im in fr[::step][:maxf]:
            c=Image.new('RGBA',(128,96),(40,44,60,255)); t=im.resize((im.width//2,im.height//2))
            a=t.split()[3].point(lambda v:int(v*max(f['alpha'],0.35))); t.putalpha(a); c.paste(t,(0,0),t); cells.append((c,f['duration']))
        return meta,cells
    L=min([f['ox'] for f,i in fr if i]+[0]); T=min([f['oy'] for f,i in fr if i]+[0])
    R=max([f['ox']+f['w'] for f,i in fr if i]+[1]); B=max([f['oy']+f['h'] for f,i in fr if i]+[1])
    W,H=max(R-L,8),max(B-T,8); cells=[]
    step=max(1,len(fr)//maxf)
    for f,im in fr[::step][:maxf]:
        c=Image.new('RGBA',(W,H),(40,44,60,255)); d=ImageDraw.Draw(c)
        ax,ay=-L,-T; d.line((ax-3,ay,ax+3,ay),fill=(255,0,255,255)); d.line((ax,ay-3,ax,ay+3),fill=(255,0,255,255))
        if im: c.paste(im,(f['ox']-L,f['oy']-T),im)
        cells.append((c,f['duration']))
    return meta,cells
def sheet_for(name,out):
    m=moves[name]; rows=[]
    for s in m['steps']:
        dirn=2 if s['direction']=='user_facing' else 0
        meta,cells=strip(s['fx'],dirn)
        rows.append((f"{s['role']}  fx {s['fx']}  where={s['where']}  attach={s['attach']}  dir={dirn if meta['directional'] else '-'}  frames={len(meta['animations']['0'])}",cells))
    W=max([sum(c.width+2 for c,_ in cells) for _,cells in rows]+[300])
    H=sum(max(c.height for c,_ in cells)+14 for _,cells in rows)+16
    img=Image.new('RGBA',(W,H),(0,0,0,255)); d=ImageDraw.Draw(img)
    d.text((2,2),f"{name}  where={m['where']} anim={m['anim']} user_anim={m['user_anim_name']} speed={m['speed']}",fill=(255,255,255,255))
    y=16
    for label,cells in rows:
        d.text((2,y),label,fill=(200,220,255,255)); y+=12; x=0
        for c,_ in cells: img.paste(c,(x,y)); x+=c.width+2
        y+=max(c.height for c,_ in cells)+2
    img=img.resize((img.width*2,img.height*2),Image.NEAREST); img.save(out)
for n in sys.argv[1:]:
    sheet_for(n,ROOT+'check/'+n.replace(' ','_')+'.png')
