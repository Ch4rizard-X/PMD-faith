import numpy as np, scipy.signal as ss, sys, json, csv
from score import prep, SR, FPS
WS=[0.5,1.0,2.0]; SPAN=10.0
def framefeat(P):
    out={}
    db=20*np.log10(P['rms']+1e-9); live=db>np.percentile(db,99.5)-45
    for k in 'MC':
        F=P[k]-P[k][:,live].mean(1,keepdims=True)
        F=F/(np.linalg.norm(F,axis=0,keepdims=True)+1e-6)
        F[:,~live]=0
        out[k]=F
    return out
def grid(FF,e0,span):
    Kmax=int(4*FPS)
    ee=np.arange(max(int(e0-span*FPS),Kmax+1),e0+1)
    rows=np.arange(ee[0]-Kmax,e0); n=e0+1
    D=np.zeros((len(rows),n))
    for k in 'MC': D+=FF[k][:,rows].T@FF[k][:,:n]
    D/=2
    Dp=np.concatenate([np.zeros((len(rows),Kmax)),D],1)
    acc=np.zeros((len(ee),n)); out={}
    cnt=lambda K: np.minimum(np.arange(n),K)
    Ks={int(W*FPS):W for W in WS+[4.0]}
    for k in range(1,Kmax+1):
        acc+=Dp[ee-k-rows[0]][:,Kmax-k:Kmax-k+n]
        if k in Ks:
            c=cnt(k).astype(float); v=acc/np.maximum(c,1)
            v[:,c<min(k,int(0.3*FPS))]=np.nan
            out[Ks[k]]=v
    return ee,out
def analyse(x):
    P=prep(x); dur=len(x)/SR; e0=int(round((dur-2.0)*FPS))
    if e0<6*FPS: return None
    FF=framefeat(P); ee,sc=grid(FF,e0,SPAN)
    tot=np.mean([sc[W] for W in WS],0)
    tot=np.nan_to_num(tot,nan=-9)
    for i,e in enumerate(ee):
        lim=min(int(0.6*e),e-int(8*FPS)); tot[i,max(lim,0):]=-9
    # an early end (e<e0) is only plausible if the music thins out after it (leftover voices / release)
    pw=P['rms']**2; cs=np.concatenate([[0],np.cumsum(pw)])
    def mdb(a,b): return 10*np.log10((cs[b]-cs[a])/max(b-a,1)+1e-12)
    drop=np.array([mdb(e-int(4*FPS),e)-mdb(e,min(e+int(2*FPS),e0)) if e<e0-int(0.3*FPS) else 0 for e in ee])
    bad=(ee<e0)&((drop<2.0)|(ee>=e0-int(0.3*FPS)))
    tot[bad]=-9
    pen=np.where(ee==e0,0.0,0.05+0.01*(e0-ee)/FPS)[:,None]
    adj=tot-pen
    i,j=np.unravel_index(np.argmax(adj),adj.shape)
    a2=adj.copy(); a2[:,max(0,j-int(.5*FPS)):j+int(.5*FPS)]=-9
    i2,j2=np.unravel_index(np.argmax(a2),a2.shape)
    c=tot[i]; off=0.0
    if 0<j<len(c)-1 and c[j-1]>-9 and c[j+1]>-9:
        a,m,z=c[j-1],c[j],c[j+1]; den=a-2*m+z; off=float(np.clip(0.5*(a-z)/den,-0.5,0.5)) if den<0 else 0.0
    w4=sc[4.0][i,j]
    from refine import stripe_end
    rs,re_,sb,sa=stripe_end(FF,(j+off)/FPS,ee[i]/FPS,e0/FPS)
    return dict(drop=float(drop[i]),rs=rs,re=re_,sb=sb,sa=sa,s=(j+off)/FPS,e=ee[i]/FPS,e0=e0/FPS,S=float(tot[i,j]),adj=float(adj[i,j]),second=float(a2[i2,j2]),second_s=j2/FPS,
                w4=float(np.nan_to_num(w4,nan=-1)),per=[float(np.nan_to_num(sc[W][i,j],nan=-1)) for W in WS],dur=dur)
if __name__=='__main__':
    rows=[r for r in csv.DictReader(open('/tmp/claude-0/up/eos/eos_audio/music_list.csv')) if r['kind']=='music' and r['loops_in_game']=='True']
    only=set(sys.argv[1:])
    todo=[r for r in rows if not only or '%03d'%int(r['id']) in only]
    from multiprocessing import Pool
    def job(r): return analyse(np.load('pcm/%03d.npy'%int(r['id'])))
    with Pool(2) as pool: outs=pool.map(job,todo)
    res={}
    for r,b in zip(todo,outs):
        tid='%03d'%int(r['id']); res[tid]=dict(name=r['name'],raw=b)
        if b: print('   refined s=%.3f e=%.3f stripe before %.2f after %.2f'%(b['rs'],b['re'],b['sb'],b['sa']))
        if b: print(tid,'%-32s s=%7.3f e=%7.3f e0=%7.3f S=%.3f adj=%.3f 2nd=%.3f@%.2f w4=%.2f per=%s'%(r['name'][:32],b['s'],b['e'],b['e0'],b['S'],b['adj'],b['second'],b['second_s'],b['w4'],['%.2f'%p for p in b['per']]),flush=True)
        else: print(tid,r['name'],'SHORT',flush=True)
    if not only: json.dump(res,open('raw.json','w'),indent=1,default=float)
