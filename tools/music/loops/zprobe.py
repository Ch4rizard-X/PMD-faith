import numpy as np, scipy.signal as ss
from score import prep,SR,FPS
from detect2 import scores,WS
import sys
ids=sys.argv[1:] or ['011','015','017','018','016','134','123']
for t in ids:
    x=np.load('pcm/%s.npy'%t); P=prep(x); e0=int(round((len(x)/SR-2)*FPS))
    ee,sc=scores(P,e0,span=0.0)
    for W in WS+['avg']:
        r=(np.mean([sc[w] for w in WS],0) if W=='avg' else sc[W])[-1]
        lim=min(int(0.6*e0),e0-int(8*FPS)); c=r[:lim].copy(); c[:int(0.2*FPS)]=-1
        pk,_=ss.find_peaks(c,distance=int(0.1*FPS)); v=np.sort(c[pk])[::-1]
        b=pk[np.argmax(c[pk])]
        z=(v[0]-np.median(v))/(v.std()+1e-9)
        print(t,W,'best %.3f@%.3f 2nd %.3f med %.3f z %.2f'%(v[0],b/FPS,v[1],np.median(v),z))
