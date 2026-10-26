import numpy as np, scipy.signal as ss
from score import *
for tid,s0,e0 in [('123',15.0,69.0),('123',19.0,73.0),('134',0.476,46.19),('017',0.057,100.057),('017',0.057,98.239)]:
    x=np.load('pcm/%s.npy'%tid); P=prep(x)
    e=int(round(e0*FPS)); g=int(round(s0*FPS))
    out=[]
    for nm in 'MCX':
        for W in [0.5,1,2]:
            c=patchcorr(P[nm],e,int(W*FPS))[:e-int(3*FPS)]
            pk,_=ss.find_peaks(c,distance=int(0.1*FPS)); v=c[max(0,g-3):g+4].max()
            out.append('%s%g:r%d(%.2f/%.2f@%.2f)'%(nm,W,(c[pk]>v).sum(),v,c[pk].max(),pk[np.argmax(c[pk])]/FPS))
    print(tid,s0,e0,' '.join(out))
