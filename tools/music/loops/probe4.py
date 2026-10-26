import numpy as np, scipy.signal as ss
from score import *
GT={'011':(4.0,30.0),'018':(3.582,118.433),'016':(32.821,133.378),'123':(15.0,77.0),'1230':(19.0,77.0)}
for tid,(s0,e0) in GT.items():
    x=np.load('pcm/%s.npy'%tid[:3]); P=prep(x)
    e=int(round((len(x)/SR-2.0)*FPS)); g=int(round(s0*FPS)); lim=int(0.6*e)
    out=[]
    for nm in 'MCX':
        for W in [0.5,1,2,4]:
            c=patchcorr(P[nm],e,int(W*FPS))[:lim]
            pk,_=ss.find_peaks(c,distance=int(0.1*FPS)); v=c[g-3:g+4].max()
            out.append('%s%g:r%d(%.2f/%.2f)'%(nm,W,(c[pk]>v).sum(),v,c[pk].max()))
    print(tid,' '.join(out))
