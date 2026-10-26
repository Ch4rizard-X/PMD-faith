# Build extra animation sheets + patch.json from SpriteCollab (sparse clone at /tmp/claude-0/scanim).
import json, os, sys, xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
SC='/tmp/claude-0/scanim'; OUT='/tmp/claude-0/sprites_extra'; SH=OUT+'/sheets'; MAXS=4096
S=json.load(open('/tmp/claude-0/pmd1/game/data/sprites.json'))
KM=json.load(open(OUT+'/gen/keymap.json'))
def parse(path):
    r=ET.parse(path).getroot(); A={}
    for a in r.iter('Anim'):
        nm=a.findtext('Name'); c=a.findtext('CopyOf')
        if c: A[nm]=('copy',c); continue
        A[nm]=('anim',int(a.findtext('FrameWidth')),int(a.findtext('FrameHeight')),[int(d.text) for d in a.iter('Duration')])
    return A
def resolve(A,nm,seen=()):
    e=A.get(nm)
    if e is None or nm in seen: return None
    return resolve(A,e[1],seen+(nm,)) if e[0]=='copy' else nm
def save_png(im,p):
    a=np.asarray(im); a=a.copy(); a[a[...,3]==0]=0  # canonical transparent
    flat=a.reshape(-1,4).view(np.uint32).ravel()
    u,inv=np.unique(flat,return_inverse=True)
    if len(u)<=256:
        cols=u.view(np.uint8).reshape(-1,4)
        P=Image.fromarray(inv.reshape(a.shape[:2]).astype(np.uint8),'P')
        P.putpalette(cols[:,:3].ravel().tolist())
        P.info['transparency']=bytes(cols[:,3].tolist())
        P.save(p,optimize=True,transparency=bytes(cols[:,3].tolist()))
    else: Image.fromarray(a,'RGBA').save(p,optimize=True)
def pack(blocks):
    # shelf packing; blocks: list of (id,w,h). returns list of sheets [(W,H,{id:(x,y)})]
    blocks=sorted(blocks,key=lambda b:(-b[2],-b[1])); sheets=[]
    for bid,w,h in blocks:
        assert w<=MAXS and h<=MAXS,(bid,w,h)
        done=False
        for sh in sheets:
            for shelf in sh['shelves']:   # [y,h,xcursor]
                if h<=shelf[1] and shelf[2]+w<=MAXS:
                    sh['pos'][bid]=(shelf[2],shelf[0]); shelf[2]+=w; done=True; break
            if done: break
            if sh['top']+h<=MAXS:
                sh['shelves'].append([sh['top'],h,w]); sh['pos'][bid]=(0,sh['top']); sh['top']+=h; done=True; break
        if not done:
            sheets.append({'shelves':[[0,h,w]],'top':h,'pos':{bid:(0,0)}})
    res=[]
    for sh in sheets:
        W=max(s[2] for s in sh['shelves']); res.append((W,sh['top'],sh['pos']))
    return res
patch={}; stats={'species':0,'anims':0,'alias':0,'alias_existing':0,'sheets':0}; nodata=[]; mism={}; skipped=[]; trimmed=[]
ONLY=sys.argv[1:]
for k in sorted(S):
    if ONLY and k not in ONLY: continue
    d=f"{SC}/{KM[k]}"; ax=d+'/AnimData.xml'
    if not os.path.exists(ax): nodata.append(k); continue
    A=parse(ax); have=S[k]['anims']
    # consistency check of existing anims vs current SpriteCollab
    for nm,e in have.items():
        src=resolve(A,nm)
        if src and (A[src][1]!=e['w'] or A[src][2]!=e['h']): mism.setdefault(k,[]).append(nm)
    blocks={}; meta={}; aliases={}
    for nm in A:
        if nm in have: continue
        src=resolve(A,nm)
        if src is None: skipped.append((k,nm,'badcopy')); continue
        if src!=nm: aliases[nm]=src; continue
        f=f'{d}/{nm}-Anim.png'
        if not os.path.exists(f): skipped.append((k,nm,'nopng')); continue
        _,fw,fh,durs=A[nm]
        with Image.open(f) as im: W,H=im.size
        cols=W//fw; rows=8 if H//fh>=8 else 1; n=min(cols,len(durs))
        if n==0: skipped.append((k,nm,'empty')); continue
        cx=cy=0
        if n*fw>MAXS or rows*fh>MAXS:   # trim empty margins symmetrically (keeps frame centre)
            with Image.open(f) as im: al=np.asarray(im.convert('RGBA'))[...,3]
            l=r=fw; t=b=fh
            for ry in range(rows):
                for cx_ in range(n):
                    c=al[ry*fh:(ry+1)*fh, cx_*fw:(cx_+1)*fw]; ys,xs=np.nonzero(c)
                    if len(xs): l=min(l,xs.min()); r=min(r,fw-1-xs.max()); t=min(t,ys.min()); b=min(b,fh-1-ys.max())
            cx=int(min(l,r)) if l<fw else 0; cy=int(min(t,b)) if t<fh else 0
            trimmed.append((k,nm,fw,fh,fw-2*cx,fh-2*cy))
            if n*(fw-2*cx)>MAXS or rows*(fh-2*cy)>MAXS: skipped.append((k,nm,'too big %dx%d'%(n*(fw-2*cx),rows*(fh-2*cy)))); continue
        blocks[nm]=(n*(fw-2*cx),rows*(fh-2*cy)); meta[nm]=(f,fw,fh,durs[:n],rows,cx,cy)
    ent={}
    if blocks:
        sheets=pack([(nm,w,h) for nm,(w,h) in blocks.items()])
        for i,(W,H,pos) in enumerate(sheets):
            name=f'x{k}.png' if i==0 else f'x{k}_{i+1}.png'
            cur=Image.new('RGBA',(W,H),(0,0,0,0))
            for nm,(x,y) in pos.items():
                f,fw,fh,durs,rows,cx,cy=meta[nm]; nw,nh=fw-2*cx,fh-2*cy; nf=len(durs)
                with Image.open(f) as im:
                    src=im.convert('RGBA')
                    for ry in range(rows):
                        for c in range(nf):
                            cur.paste(src.crop((c*fw+cx,ry*fh+cy,c*fw+cx+nw,ry*fh+cy+nh)),(x+c*nw,y+ry*nh))
                ent[nm]={'x':x,'y':y,'w':nw,'h':nh,'dur':durs,'rows':rows,'s':name}
            save_png(cur,f'{SH}/{name}'); stats['sheets']+=1
    for nm,src in aliases.items():
        if src in ent: ent[nm]=dict(ent[src]); stats['alias']+=1
        elif src in have:
            e=dict(have[src]); e.setdefault('s',S[k]['sheet']); ent[nm]=e; stats['alias_existing']+=1
        else: skipped.append((k,nm,'alias->missing '+src))
    if ent:
        patch[k]={nm:ent[nm] for nm in sorted(ent)}; stats['species']+=1; stats['anims']+=len(ent)
json.dump(patch,open(OUT+'/patch.json','w'),separators=(',',':'))
json.dump({'stats':stats,'nodata':nodata,'size_mismatch_existing':mism,'skipped':skipped,'trimmed':trimmed},open(OUT+'/gen/report.json','w'),indent=1)
print(stats,'nodata',nodata,'mismatch species',len(mism),'skipped',len(skipped))
