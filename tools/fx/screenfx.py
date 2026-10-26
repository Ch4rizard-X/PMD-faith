import struct, numpy as np
from wanfx import entries, sir0, u16, u32
def load_screen(idx):
    b,hdr,_=sir0(entries()[idx])
    nF,pAnim,u3,pImg,pPal=struct.unpack_from('<5I',b,hdr)
    ncol=(pImg-pPal)//4
    cols=[(b[pPal+4*i],b[pPal+4*i+1],b[pPal+4*i+2]) for i in range(ncol)]
    raw=np.frombuffer(b[pImg:hdr],np.uint8)
    px=np.stack([raw&15,raw>>4],1).reshape(-1)
    frames=[]
    ptrs=[u32(b,pAnim+4*i) for i in range(nF)]
    for p in ptrs:
        row_h=u16(b,p+6); dur=u16(b,p+8); alpha=u16(b,p+28)
        o=p+36; pieces=[]; tot=0
        while tot<row_h*33:
            v=u16(b,o); o+=2
            skip=(v&0x8000)==0; arg=v&0x3FF
            pieces.append((arg,bool(v&0x400),bool(v&0x800),skip,(v>>12)&7))
            tot+= arg if skip else 1
        frames.append(dict(dur=dur,alpha=alpha,rows=row_h,pieces=pieces))
    return dict(colors=cols,px=px,frames=frames,unk=(u3,))
def render_frame(s,f,use_alpha=True):
    img=np.zeros((f['rows']*8 if f['rows'] else 8,33*8,4),np.uint8)
    pal=s['colors']; blk=0
    PL=[np.array([list(pal[r*16+i])+[255] for i in range(16)],np.uint8) for r in range(len(pal)//16)]
    a=255
    if use_alpha: a=min(255,f['alpha']>>8) if f['alpha'] else 255
    for idx,fx,fy,skip,pl in f['pieces']:
        if skip: blk+=idx; continue
        t=s['px'][idx*64:idx*64+64]
        if len(t)<64: t=np.concatenate([t,np.zeros(64-len(t),np.uint8)])
        t=t.reshape(8,8)
        if fx: t=t[:,::-1]
        if fy: t=t[::-1,:]
        bx,by=(blk%33)*8,(blk//33)*8
        if by+8<=img.shape[0]:
            lut=PL[pl]; lut[:,3]=np.where(np.arange(16)>0,a,0)
            img[by:by+8,bx:bx+8]=np.where((t>0)[...,None],lut[t],img[by:by+8,bx:bx+8])
        blk+=1
    return img[:,:256]
