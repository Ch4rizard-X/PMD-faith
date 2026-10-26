import struct,sys,glob
def vlq(d,i):
    v=0
    while True:
        b=d[i];i+=1;v=(v<<7)|(b&0x7f)
        if b<0x80: return v,i
def parse(fn):
    d=open(fn,'rb').read()
    fmt,nt,div=struct.unpack('>HHH',d[8:14]); i=14; tracks=[]
    for t in range(nt):
        assert d[i:i+4]==b'MTrk'; L=struct.unpack('>I',d[i+4:i+8])[0]; j=i+8; end=j+L; i=end
        tick=0; rs=None; ev=[]
        while j<end:
            dt,j=vlq(d,j); tick+=dt; b=d[j]
            if b==0xff:
                typ=d[j+1]; l,k=vlq(d,j+2); data=d[k:k+l]; j=k+l; ev.append((tick,'meta',typ,data))
            elif b in (0xf0,0xf7):
                l,k=vlq(d,j+1); j=k+l
            else:
                if b&0x80: rs=b; j+=1
                st=rs; n=2 if (st>>4) not in (0xc,0xd) else 1
                ev.append((tick,'ev',st,d[j:j+n])); j+=n
        tracks.append(ev)
    return div,tracks
def info(fn):
    div,tracks=parse(fn)
    tempos=sorted([(e[0],struct.unpack('>I',b'\0'+e[3])[0]) for tr in tracks for e in tr if e[1]=='meta' and e[2]==0x51],key=lambda x:x[0])
    # last at same tick wins: stable sort keeps file order
    tm={}
    for t,u in tempos: tm[t]=u
    tl=sorted(tm.items())
    def t2s(tick):
        s=0;pt=0;pu=500000
        for t,u in tl:
            if t>=tick: break
            s+=(t-pt)*pu/div/1e6; pt=t; pu=u
        return s+(tick-pt)*pu/div/1e6
    marks=[(e[0],e[2],e[3]) for tr in tracks for e in tr if e[1]=='meta' and e[2] in (1,6)]
    ts=[(e[0],tuple(e[3])) for tr in tracks for e in tr if e[1]=='meta' and e[2]==0x58]
    ends=[tr[-1][0] for tr in tracks if tr]
    notes=[e[0] for tr in tracks for e in tr if e[1]=='ev' and (e[2]>>4)==9 and e[3][1]>0]
    return dict(div=div,tempos=tl,marks=[(t,round(t2s(t),3),ty,m) for t,ty,m in marks],ts=ts,end=max(ends),end_s=t2s(max(ends)),firstnote=t2s(min(notes)),lastnote=t2s(max(notes)),t2s=t2s)
if __name__=='__main__':
    for fn in sorted(glob.glob('/tmp/claude-0/up/eos/midi/*.mid')):
        r=info(fn); print(fn.split('/')[-1],'div',r['div'],'tempos',[(t,round(6e7/u,2)) for t,u in r['tempos']][:6],'ts',r['ts'][:3])
        print('   marks',r['marks'][:12],'end',round(r['end_s'],3),'first',round(r['firstnote'],3),'last',round(r['lastnote'],3))
