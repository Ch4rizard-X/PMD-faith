from wanfx import *; from tables import *
from PIL import Image
import sys
vM,vE,vS=vanilla()
def own_rows(w):
    return rows_of(w.colors)
def palfn_for(e,w,mode):
    base=base_rows(); own=own_rows(w) if e['type']==3 else []
    off=(w.unk5&15) if (e['type']==3 and w.unk5>>8) else 0
    comb=[list(r) for r in base]+[[(0,0,0)]*16]*4
    comb=comb[:16]
    for k,r in enumerate(own):
        if off+k<16: comb[off+k]=r
    pn=e['pal']
    def P(p): return comb[p['pal']] if p['keep_pal'] else comb[pn]
    def A(p): return comb[p['pal']]
    return {'A':A,'P':P}[mode]
def strip(effid, mode, dirn=0):
    e=vE[effid]
    if e['type']==1: wa=load(0); wi=load(292)
    else: wa=wi=load(e['file'])
    ai=e['anim_idx']
    if len(wa.groups[0])%8==0: ai+=dirn
    seq=wa.groups[0][ai]
    pf=palfn_for(e,wi,mode)
    frames=[]
    for s_ in seq:
        r=compose(wa,wi,s_['frame'],pf)
        if r: frames.append(r)
    if not frames: return Image.new('RGBA',(8,8))
    L=min(f[1] for f in frames); T=min(f[2] for f in frames)
    R=max(f[1]+f[0].shape[1] for f in frames); B=max(f[2]+f[0].shape[0] for f in frames)
    n=len(frames); cols=min(n,12); rows=(n+cols-1)//cols
    W,H=R-L,B-T
    out=Image.new('RGBA',(cols*W,rows*H),(40,40,60,255))
    for k,(a,l,t) in enumerate(frames):
        im=Image.fromarray(a,'RGBA')
        out.paste(im,((k%cols)*W+l-L,(k//cols)*H+t-T),im)
    return out
if __name__=='__main__':
    effs=[int(x) for x in sys.argv[2].split(',')]
    modes=sys.argv[3].split(',')
    ims=[strip(e,m) for e in effs for m in modes]
    W=max(i.width for i in ims); H=sum(i.height+4 for i in ims)
    out=Image.new('RGBA',(W,H),(0,0,0,255)); y=0
    for i in ims: out.paste(i,(0,y)); y+=i.height+4
    out=out.resize((out.width*2,out.height*2),Image.NEAREST)
    out.save(sys.argv[1])
