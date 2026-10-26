"""Export every effect animation referenced by move animations into sheets/fx_NNNN.png + .json."""
import json, os, sys, hashlib
import numpy as np
from PIL import Image
from tables import vanilla, remixed
from wanfx import load, base_rows, rows_of, compose
from screenfx import load_screen, render_frame

OUT='/tmp/claude-0/eos/moveanim/sheets'
os.makedirs(OUT,exist_ok=True)
POINT={0:'head',1:'left_hand',2:'right_hand',3:'center',-1:'none'}
TYPE={1:'wan_file0',2:'wan_file1',3:'wan',4:'wat',5:'screen',6:'wba'}

def palette_table(e,w):
    comb=[list(r) for r in base_rows()]
    while len(comb)<16: comb.append([(0,0,0)]*16)
    comb=comb[:16]
    if e['type']==3 and w.unk5 is not None and (w.unk5>>8):
        off=w.unk5&0xFF
        for k,r in enumerate(rows_of(w.colors)):
            if off+k<16: comb[off+k]=list(r)
    return comb

def pack(images):
    """Shelf-pack list of (key, RGBA array). Returns sheet Image and {key:(x,y,w,h)}."""
    items=sorted([(k,a) for k,a in images if a is not None],key=lambda t:-t[1].shape[0])
    total=sum(a.shape[0]*a.shape[1] for _,a in items) or 1
    maxw=max([a.shape[1] for _,a in items]+[1])
    W=max(maxw,min(2048,int((total**0.5)*1.3)+8))
    x=y=rowh=0; pos={}
    for k,a in items:
        h,w=a.shape[:2]
        if x+w>W: x=0; y+=rowh+1; rowh=0
        pos[k]=(x,y,w,h); x+=w+1; rowh=max(rowh,h)
    H=y+rowh if items else 1
    sheet=np.zeros((max(H,1),W,4),np.uint8)
    for k,a in items:
        x0,y0,w,h=pos[k]; sheet[y0:y0+h,x0:x0+w]=a
    return Image.fromarray(sheet,'RGBA'),pos

def trim(a):
    m=a[...,3]>0
    if not m.any(): return None,0,0
    ys,xs=np.where(m)
    return a[ys.min():ys.max()+1,xs.min():xs.max()+1],int(xs.min()),int(ys.min())

def export_sprite(fx,e):
    if e['type']==1: wa=load(0); wi=load(292); fdesc={'anim_file':0,'image_file':292}
    elif e['type']==2: wa=wi=load(1); fdesc={'anim_file':1,'image_file':1}
    else: wa=wi=load(e['file']); fdesc={'anim_file':e['file'],'image_file':e['file']}
    comb=palette_table(e,wi); pn=e['pal']
    def palfn(p): return comb[p['pal']] if p['keep_pal'] else comb[pn&15]
    anims=wa.groups[0]; ai=e['anim_idx']
    directional = len(anims)%8==0 and ai+7 < len(anims)
    keys = list(range(8)) if directional else [0]
    cache={}; imgs=[]; out={}
    for d in keys:
        seq=anims[ai+d] if directional else anims[ai]
        frames=[]
        for s in seq:
            ck=s['frame']
            if ck not in cache:
                r=compose(wa,wi,s['frame'],palfn)
                if r is None: cache[ck]=None
                else:
                    a,l,t=r; ta,dx,dy=trim(a)
                    if ta is None: cache[ck]=None
                    else:
                        cache[ck]=('m%d'%ck,l+dx,t+dy); imgs.append(('m%d'%ck,ta))
            c=cache[ck]
            frames.append(dict(key=c[0] if c else None,ox=(c[1] if c else 0)+s['ox'],oy=(c[2] if c else 0)+s['oy'],duration=s['dur'],metaframe=s['frame']))
        out[str(d)]=frames
    sheet,pos=pack(imgs)
    for d,frames in out.items():
        for f in frames:
            k=f.pop('key')
            if k is None: f.update(x=0,y=0,w=0,h=0)
            else:
                x,y,w,h=pos[k]; f.update(x=x,y=y,w=w,h=h)
    meta=dict(fx=fx,kind='sprite',effect_type=TYPE[e['type']],source=dict(effect_bin=fdesc,anim_index=ai,palette_num=pn),
              directional=directional,anchor='attach point (see README); ox/oy = top-left of frame relative to anchor, +y down',
              animations=out)
    return sheet,meta

def export_screen(fx,e):
    fi=268+e['file']; s=load_screen(fi)
    imgs=[]; seen={}; frames=[]
    for i,f in enumerate(s['frames']):
        a=render_frame(s,f,use_alpha=False)
        h=hashlib.md5(a.tobytes()).hexdigest()
        if h not in seen:
            seen[h]='s%d'%i; imgs.append((seen[h],a))
        frames.append(dict(key=seen[h],ox=0,oy=0,duration=f['dur'],alpha=round(min(f['alpha'],65280)/65280,4)))
    sheet,pos=pack(imgs)
    for f in frames:
        x,y,w,h=pos[f.pop('key')]; f.update(x=x,y=y,w=w,h=h)
    meta=dict(fx=fx,kind='screen',effect_type='screen',source=dict(effect_bin=dict(screen_file=fi),anim_index=e['anim_idx'],palette_num=e['pal']),
              directional=False,anchor='top-left of the 256x192 DS screen (frames may be taller than 192; extra rows are offscreen)',
              animations={'0':frames})
    return sheet,meta

def main():
    vM,vE,vS=vanilla(); rM,rE,rS=remixed()
    ref=sorted(set(a for M in (vM,rM) for m in M for a in m['anim'] if a>0))
    if len(sys.argv)>1: ref=[int(x) for x in sys.argv[1].split(',')]
    index={}
    for fx in ref:
        e=rE[fx]
        if e['type']==5: sheet,meta=export_screen(fx,e)
        elif e['type'] in (1,2,3): sheet,meta=export_sprite(fx,e)
        else:
            index[fx]=dict(type=TYPE.get(e['type']),skipped=True); continue
        meta.update(sfx=None if e['sfx']<0 else e['sfx'],attach_point=POINT.get(e['point'],e['point']),
                    loop=bool(e['loop']),non_blocking=bool(e['nonblock']),screen_flag=bool(e['screen']),
                    image=f'fx_{fx:04d}.png',fps=60)
        sheet.save(f'{OUT}/fx_{fx:04d}.png',optimize=True)
        json.dump(meta,open(f'{OUT}/fx_{fx:04d}.json','w'),indent=1)
        index[fx]=dict(kind=meta['kind'],directional=meta['directional'],frames=len(meta['animations']['0']))
    json.dump(index,open('/tmp/claude-0/eos/moveanim/work/fx_index.json','w'),indent=1)
    print(len(index),'exported')
main()
