import numpy as np, scipy.signal as ss
from score import *
from tempo import onset_env
GT={'011':(4.0,30.0),'015':(0,45.283),'017':(0.057,100.057),'018':(3.582,118.433),'016':(32.821,133.378),'134':(0.476,48.730),'123':(15.0,77.0)}
for tid,(s0,e0) in GT.items():
    x=np.load('pcm/%s.npy'%tid); P=prep(x)
    e=int(round((len(x)/SR-2.0)*FPS)); g=int(round(s0*FPS))
    o=onset_env(P)
    comps={}
    for nm in 'MCX':
        for W in [0.5,1,2,4]:
            comps[nm+str(W)]=patchcorr(P[nm],e,int(W*FPS))
    tot=np.mean([comps[k] for k in comps if not k.endswith('4')],0)
    lim=int(0.6*e)
    pk,_=ss.find_peaks(tot[:lim],distance=int(0.15*FPS))
    pk=pk[np.argsort(-tot[pk])][:6]
    print(tid,s0,'gt tot %.3f onset@gt %.2f'%(tot[g],o[max(0,g-2):g+3].max()),' '.join('%.3f:%.3f(o%.2f)'%(p/FPS,tot[p],o[max(0,p-2):p+3].max()) for p in pk))
