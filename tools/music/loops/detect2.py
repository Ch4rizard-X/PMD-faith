import numpy as np, scipy.signal as ss, sys, json
from score import prep, SR, FPS
WS=[0.5,1.0,2.0]
def framefeat(P):
    out={}
    for k in 'MC':
        F=P[k]-P[k].mean(1,keepdims=True)
        out[k]=F/(np.linalg.norm(F,axis=0,keepdims=True)+1e-6)
    return out
def scores(P,e0,span=3.5,feats='MC'):
    """returns ee (end frames), and dict W-> array [len(ee), e0+1] of window sims (s index = frame)"""
    FF=framefeat(P); Kmax=int(max(WS)*FPS)
    ee=np.arange(max(int(e0-span*FPS),Kmax+1),e0+1)
    rows=np.arange(ee[0]-Kmax,e0)          # frames that can appear in end windows
    n=e0+1
    D=np.zeros((len(rows),n))
    for k in feats: D+=FF[k][:,rows].T@FF[k][:,:n]
    D/=len(feats)
    # pad columns on left with zeros for s-k<0 (treated as 0 similarity)
    Dp=np.concatenate([np.zeros((len(rows),Kmax)),D],1)
    out={}
    for W in WS:
        K=int(W*FPS); res=np.zeros((len(ee),n))
        for k in range(1,K+1):
            # frame e-k vs frame s-k
            ri=ee-k-rows[0]
            res+=Dp[ri][:, Kmax-k:Kmax-k+n]
        out[W]=res/K
    return ee,out
def analyse(x,verbose=False,epen=0.02):
    P=prep(x); dur=len(x)/SR; e0=int(round((dur-2.0)*FPS))
    if e0<6*FPS: return None
    ee,sc=scores(P,e0)
    tot=np.mean([sc[W] for W in WS],0)
    for i,e in enumerate(ee):
        lim=min(int(0.6*e),e-int(8*FPS)); tot[i,max(lim,0):]=-9
    tot[:,:int(0.2*FPS)]=-9
    pen=np.where(ee==e0,0,0.03+epen*(e0-ee)/FPS)[:,None]
    adj=tot-pen
    i,j=np.unravel_index(np.argmax(adj),adj.shape)
    # second best: exclude +-0.5s in s (any e)
    a2=adj.copy(); a2[:,max(0,j-int(.5*FPS)):j+int(.5*FPS)]=-9
    i2,j2=np.unravel_index(np.argmax(a2),a2.shape)
    # best with e fixed at e0
    r0=tot[-1]; j0=int(np.argmax(r0))
    c=tot[i]; off=0
    if 0<j<len(c)-1:
        a,m,z=c[j-1],c[j],c[j+1]; den=a-2*m+z; off=0.5*(a-z)/den if den<0 else 0
    return dict(s=(j+off)/FPS,e=ee[i]/FPS,sc=float(adj[i,j]),raw=float(tot[i,j]),sec=float(a2[i2,j2]),sec_s=j2/FPS,e0=e0/FPS,s_e0=j0/FPS,sc_e0=float(r0[j0]),
                per={W:float(sc[W][i,j]) for W in WS})
if __name__=='__main__':
    GT={'011':(4.0,30.0),'015':(0,45.283),'017':(0.057,100.057),'018':(3.582,118.433),'016':(32.821,133.378),'134':(0.476,48.730),'123':(15.0,77.0)}
    for t,(s0,e0) in GT.items():
        b=analyse(np.load('pcm/%s.npy'%t)); print(t,s0,e0,{k:(round(v,3) if isinstance(v,float) else v) for k,v in b.items()})
