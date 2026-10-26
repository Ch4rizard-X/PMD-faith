import numpy as np, sys
from feats import *
GT={'011':(4.0,30.0),'015':(0,45.283),'017':(0.057,100.057),'018':(3.582,118.433),'016':(32.821,133.378),'134':(0.476,48.730),'123':(15.0,77.0)}
def unit(F):
    F=F-F.mean(1,keepdims=True) if False else F
    return F/(np.linalg.norm(F,axis=0,keepdims=True)+1e-9)
for tid,(s0,e0) in GT.items():
    x=np.load('pcm/%s.npy'%tid); mel,ch,rms=feats(x); fps=SR/HOP
    melc=mel-np.median(mel,1,keepdims=True)
    for name,F in [('mel',unit(np.maximum(mel-np.log(1e-4),0))),('chroma',unit(ch))]:
        e=int(round((len(x)/SR-2.0)*fps))
        for W in [1.0,3.0]:
            K=int(W*fps); T=F[:,e-K:e]
            # sim(s)=mean_k F[:,s-K+k].T[:,k]
            Fp=np.concatenate([np.zeros((F.shape[0],K)),F],1)
            sim=np.zeros(e+1)
            for d in range(F.shape[0]):
                sim+=np.correlate(Fp[d,:e+K],T[d],'valid')[:e+1]
            sim/=K
            sim[e-int(2*fps):]=0
            top=np.argsort(-sim)[:5]
            print(tid,name,W,'gt',s0,'sim@gt %.3f'%sim[int(round(s0*fps))],'top',[(round(i/fps,3),round(sim[i],3)) for i in top])
