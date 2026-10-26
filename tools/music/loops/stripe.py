import numpy as np
from score import prep,SR,FPS
from detect2 import framefeat
def stripe(x,s,e):
    P=prep(x); FF=framefeat(P); si=int(round(s*FPS)); ei=int(round(e*FPS))
    d=np.arange(1,si)
    v=np.mean([np.sum(FF[k][:,si-d]*FF[k][:,ei-d],0) for k in 'MC'],0)
    return d/FPS,v
import sys
for t,s,e in [('016',32.821,133.364),('017',19.946,100.055),('011',3.994,30.0),('018',3.587,118.213),('015',8.754,45.279),('123',2.821,77.0)]:
    d,v=stripe(np.load('pcm/%s.npy'%t),s,e)
    seg=[np.mean(v[int(a*FPS):int((a+1)*FPS)]) for a in range(int(d[-1]))]
    print(t,s,'per-second sims back from s:',' '.join('%.2f'%q for q in seg[:40]))
