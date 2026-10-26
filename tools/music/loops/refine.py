import numpy as np
from score import FPS
def stripe_end(FF,s,e,e0,search=1.5,K=0.3):
    """Along lag L=e-s find where the lag-L match ends (step down). Returns refined (s,e,stripe_before,stripe_after)."""
    L=int(round((e-s)*FPS)); si=int(round(s*FPS)); k=int(K*FPS); e0f=int(round(e0*FPS))
    lo=max(k,si-int(search*FPS)); hi=min(si+int(search*FPS), e0f-L)   # e=t+L must stay <= e0
    n=FF['M'].shape[1]
    ts=np.arange(max(0,lo-k),min(hi+k,n-L))
    d=np.mean([np.sum(FF[f][:,ts]*FF[f][:,ts+L],0) for f in 'MC'],0)
    best=None
    for t in range(lo,hi+1):
        i=t-ts[0]
        if i-k<0: 
            b=d[:i].mean() if i>3 else np.nan
        else: b=d[i-k:i].mean()
        a=d[i:i+k].mean() if i+k<=len(d) else -1.0  # past end of data => tail => mismatch
        if np.isnan(b): continue
        sc=b-a
        if best is None or sc>best[0]: best=(sc,t,b,a)
    if best is None: return s,e,np.nan,np.nan
    _,t,b,a=best
    return t/FPS,(t+L)/FPS,float(b),float(a)
