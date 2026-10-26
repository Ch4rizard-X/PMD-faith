import numpy as np, sys
from score import prep,SR,FPS
from detect2 import framefeat
def pairsim(FF,s,e,W):
    si=int(round(s*FPS)); ei=int(round(e*FPS)); K=int(W*FPS)
    k=np.arange(1,min(K,si)+1) if si>0 else np.array([],int)
    if len(k)==0: return float('nan')
    return float(np.mean([np.mean(np.sum(FF[f][:,si-k]*FF[f][:,ei-k],0)) for f in 'MC']))
if __name__=='__main__':
    t=sys.argv[1]; FF=framefeat(prep(np.load('pcm/%s.npy'%t)))
    for a in sys.argv[2:]:
        s,e=map(float,a.split(','))
        print(t,s,e,' '.join('W%.1f:%.3f'%(W,pairsim(FF,s,e,W)) for W in [0.5,1,2,4]))
