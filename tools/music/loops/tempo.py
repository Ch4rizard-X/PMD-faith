import numpy as np
from score import *
def onset_env(P):
    o=P['X'].sum(0); o=o-np.convolve(o,np.ones(31)/31,'same'); o=np.maximum(o,0)
    return o/(o.max()+1e-9)
def tempo(P,e):
    o=onset_env(P)[:e]
    n=len(o); ac=np.correlate(o,o,'full')[n-1:]/np.arange(n,0,-1)
    lo,hi=int(0.3*FPS),int(1.0*FPS)   # beat period 0.3..1.0 s (60..200bpm)
    # comb-score per period: phase anchored at 0, sum env at k*p, with sub-frame interpolation
    best=None; cands=[]
    for p in np.arange(lo,hi,0.25):
        k=np.arange(0,n/p-1); idx=k*p
        i0=np.floor(idx).astype(int); fr=idx-i0
        v=o[i0]*(1-fr)+o[np.minimum(i0+1,n-1)]*fr
        # allow +-1 frame slop by max over neighbors
        v2=np.maximum(v,np.maximum(o[np.maximum(i0-1,0)],o[np.minimum(i0+1,n-1)]))
        cands.append((v2.mean(),p))
    cands=np.array(cands)
    # normalize vs mean env, prefer periods whose double/half also scores (meter)
    s=cands[:,0]/o.mean()
    i=int(np.argmax(s)); p=cands[i,1]
    # fine refine
    fine=[]
    for q in np.arange(p-0.3,p+0.3,0.005):
        idx=np.arange(0,n/q-1)*q; i0=np.round(idx).astype(int); fine.append((o[i0].mean(),q))
    q=max(fine)[1]
    return q/FPS, s[i]
if __name__=='__main__':
    GT={'011':None,'015':106,'017':132,'018':134,'016':148,'134':126,'123':160}
    for t,b in GT.items():
        x=np.load('pcm/%s.npy'%t); P=prep(x); e=int(round((len(x)/SR-2)*FPS))
        q,s=tempo(P,e); print(t,'est beat %.4f s = %.2f bpm  strength %.2f   true %s'%(q,60/q,s,b))
