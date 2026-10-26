import numpy as np, scipy.signal as ss
from feats import *
FPS=SR/HOP
def prep(x):
    mel,ch,rms=feats(x)
    db=mel*10/np.log(10)
    top=np.percentile(db,99.5)
    M=np.maximum(db-(top-60),0)
    rdb=20*np.log10(rms+1e-9); loud=np.clip((rdb-(np.percentile(rdb,99.5)-50))/50,0,1)
    C=ch*loud
    flux=np.maximum(np.diff(M,axis=1,prepend=M[:,:1]),0)
    # coarse 16-band flux
    Fx=flux.reshape(16,4,-1).sum(1)
    return dict(M=M,C=C,X=Fx,rms=rms,n=M.shape[1],loud=loud)
def patchcorr(F,e,K,pad=0.0):
    """Pearson corr between patch F[:,s-K:s] and F[:,e-K:e] for s in 0..e; pre-start padded with pad."""
    d=F.shape[0]
    T=F[:,e-K:e]; Tc=T-T.mean(); nT=np.sqrt((Tc**2).sum())
    Fp=np.concatenate([np.full((d,K),pad),F[:,:e]],1)   # patch for s = Fp[:,s:s+K]
    num=np.zeros(e+1)
    for i in range(d):
        num+=ss.fftconvolve(Fp[i],Tc[i][::-1],'valid')[:e+1]
    c1=np.concatenate([[0],np.cumsum(Fp.sum(0))]); c2=np.concatenate([[0],np.cumsum((Fp**2).sum(0))])
    S1=c1[K:K+e+1]-c1[:e+1]; S2=c2[K:K+e+1]-c2[:e+1]
    var=np.maximum(S2-S1**2/(d*K),1e-9)
    return num/(np.sqrt(var)*nT+1e-9)
