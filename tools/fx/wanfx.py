import struct, sys
sys.path.insert(0,'/tmp/claude-0/eos/tools')
from eoslib import pack_entries
import numpy as np
EFFECT='/tmp/claude-0/eos/fs/EFFECT/effect.bin'
_P=None
def entries():
    global _P
    if _P is None: _P=pack_entries(open(EFFECT,'rb').read())
    return _P
DIM_TABLE=[(1,1),(2,2),(4,4),(8,8),(2,1),(4,1),(4,2),(8,4),(1,2),(1,4),(2,4),(4,8)]
def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def s16(d,o): return struct.unpack_from('<h',d,o)[0]
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
def sir0(b):
    assert b[:4]==b'SIR0'
    dp,po=struct.unpack_from('<II',b,4)
    # decode pointer offsets list
    offs=[];cur=0;i=po;acc=0
    while i<len(b):
        v=0
        while True:
            c=b[i];i+=1
            v=(v<<7)|(c&0x7f)
            if not c&0x80: break
        if v==0: break
        cur+=v; offs.append(cur)
    return b,dp,set(offs)
class Wan:
    pass
def load(idx):
    b,hdr,ptrs=sir0(entries()[idx])
    w=Wan(); w.idx=idx
    pAnim,pImg=u32(b,hdr),u32(b,hdr+4)
    w.imgType=u16(b,hdr+8); w.unk12=u16(b,hdr+10)
    w.pal_rows=[]; w.palOffset=0; w.is256=0; w.unk5=None; w.tiles=None
    if pImg:
        pTab,pPal=u32(b,pImg),u32(b,pImg+4)
        w.is256=u16(b,pImg+10); nImg=u16(b,pImg+14)
        pPalData=u32(b,pPal); w.palUnk=(u16(b,pPal+4),u16(b,pPal+6),u16(b,pPal+8)); w.unk5=u16(b,pPal+10)
        ncol=(pPal-pPalData)//4
        cols=[(b[pPalData+4*i],b[pPalData+4*i+1],b[pPalData+4*i+2]) for i in range(ncol)]
        w.colors=cols
        imgs=[u32(b,pTab+4*i) for i in range(nImg)]
        w.imgptrs=imgs
        if w.imgType==3:
            pSrc=u32(b,imgs[0]); w.atlasW=u16(b,imgs[0]+4); w.atlasH=u16(b,imgs[0]+6)
            raw=b[pSrc:imgs[0]]
            w.atlas=raw
        else:
            w.images=[]
            for p in imgs:
                px=bytearray(); o=p
                while True:
                    src=u32(b,o); amt=u16(b,o+4)
                    if src==0 and amt==0: break
                    if src==0 or o not in ptrs and False: px+=bytes(amt)
                    else: px+=b[src:src+amt]
                    o+=12
                w.images.append(bytes(px))
    w.frames=None; w.groups=None
    if pAnim:
        pMF=u32(b,pAnim); pGT=u32(b,pAnim+8); nG=u16(b,pAnim+12)
        groups=[]; firstSeq=None
        for g in range(nG):
            loc=u32(b,pGT+8*g); n=u16(b,pGT+8*g+4)
            seqp=[u32(b,loc+4*k) for k in range(n)] if loc else []
            if loc and firstSeq is None: firstSeq=loc
            groups.append(seqp)
        mfp=[]; o=pMF
        end=firstSeq if firstSeq else pGT
        while o<end: mfp.append(u32(b,o)); o+=4
        frames=[]
        for p in mfp:
            pieces=[]; o=p
            if w.imgType==3:
                frames.append(None); continue
            while True:
                imgIdx=s16(b,o); unk=u16(b,o+2); y=u16(b,o+4); x=u16(b,o+6); attr2=u16(b,o+8); blk=attr2&0x3FF; pal=attr2>>12; extra=(attr2>>10)&3
                draw=b[o+3]
                dimType=y>>14; dimData=x>>11
                end_=dimData&1; hf=bool(dimData&2); vf=bool(dimData&4)
                res=DIM_TABLE[dimType*4+(dimData>>3)]
                pieces.append(dict(keep_pal=bool(x&0x400),tile=blk,prio=extra,img=imgIdx,unk=unk,raw=b[o:o+10],x=x&0x1FF,y=y&0x3FF,yflags=(y>>10)&0xF,blk=blk,pal=pal,hf=hf,vf=vf,w=res[0],h=res[1],front=(draw==0)))
                o+=10
                if end_: break
            frames.append(pieces)
        w.frames=frames
        w.groups=[]
        for seqs in groups:
            anims=[]
            for sp in seqs:
                seq=[];o=sp
                while True:
                    dur=u16(b,o); fi=u16(b,o+2); ox=s16(b,o+4); oy=s16(b,o+6); u1=u16(b,o+8); u2=u16(b,o+10)
                    if dur==0: break
                    seq.append(dict(dur=dur,frame=fi,ox=ox,oy=oy,u1=u1,u2=u2)); o+=12
                anims.append(seq)
            w.groups.append(anims)
    return w

# ---------------- rendering ----------------
def tile_bytes(w):
    """Concatenated image data with each image padded to a 128-byte boundary (8bpp: units of 2 tiles)."""
    if hasattr(w,'_tb'): return w._tb
    out=bytearray()
    for im in w.images:
        out+=im
        while len(out)%128: out+=b'\0'
    w._tb=bytes(out); return w._tb
def piece_indices(w_img, p):
    """Return HxW numpy array of palette indices (0 = transparent) for a piece, with flips applied."""
    W,H=p['w']*8,p['h']*8
    tb=tile_bytes(w_img)
    if w_img.is256:
        base=p['tile']*128
        arr=np.zeros((H,W),np.uint8)
        t=0
        for ty in range(p['h']):
            for tx in range(p['w']):
                o=base+t*64; chunk=tb[o:o+64]
                if len(chunk)<64: chunk=chunk+bytes(64-len(chunk))
                arr[ty*8:ty*8+8,tx*8:tx*8+8]=np.frombuffer(chunk,np.uint8).reshape(8,8)
                t+=1
    else:
        base=p['tile']*128
        arr=np.zeros((H,W),np.uint8); t=0
        for ty in range(p['h']):
            for tx in range(p['w']):
                o=base+t*32; chunk=tb[o:o+32]
                if len(chunk)<32: chunk=chunk+bytes(32-len(chunk))
                a=np.frombuffer(chunk,np.uint8)
                px=np.stack([a&15,a>>4],1).reshape(8,8)
                arr[ty*8:ty*8+8,tx*8:tx*8+8]=px; t+=1
    if p['hf']: arr=arr[:,::-1]
    if p['vf']: arr=arr[::-1,:]
    return arr

def rows_of(colors):
    return [colors[i*16:(i+1)*16] for i in range(len(colors)//16)]
_BASE=None
def base_rows():
    global _BASE
    if _BASE is None: _BASE=rows_of(load(292).colors)
    return _BASE
CX,CY=256,512
def compose(w_anim, w_img, frame_idx, palfn):
    """Compose metaframe -> (RGBA array, left, top) relative to anchor; palfn(piece_pal)->16 RGB tuples."""
    pieces=w_anim.frames[frame_idx] if frame_idx < len(w_anim.frames) else None
    if not pieces: return None
    L=min(p['x']-CX for p in pieces); T=min(p['y']-CY for p in pieces)
    R=max(p['x']-CX+p['w']*8 for p in pieces); B=max(p['y']-CY+p['h']*8 for p in pieces)
    img=np.zeros((B-T,R-L,4),np.uint8)
    # pieces are listed front-to-back in OAM order: draw in reverse so earlier pieces end on top
    for p in reversed(pieces):
        idx=piece_indices(w_img,p)
        row=palfn(p)
        lut=np.zeros((256,4),np.uint8)
        for v in range(1,256):
            c=v&15 if w_img.is256 else v
            if w_img.is256 and (v<16 or v>31): continue
            if c==0: continue
            r,g,b_=row[c]; lut[v]=(r,g,b_,255)
        rgba=lut[idx]
        x0=p['x']-CX-L; y0=p['y']-CY-T
        sub=img[y0:y0+idx.shape[0],x0:x0+idx.shape[1]]
        m=rgba[...,3]>0
        sub[m]=rgba[m]
    return img,L,T
