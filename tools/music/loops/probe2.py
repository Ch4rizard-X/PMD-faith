import numpy as np
from score import *
GT={'011':(4.0,30.0),'015':(0,45.283),'017':(0.057,100.057),'018':(3.582,118.433),'016':(32.821,133.378),'134':(0.476,48.730),'123':(15.0,77.0)}
for tid,(s0,e0) in GT.items():
    x=np.load('pcm/%s.npy'%tid); P=prep(x)
    e=int(round((len(x)/SR-2.0)*FPS)); g=int(round(s0*FPS))
    out=[]
    for nm in 'MCX':
        for W in [0.25,0.5,1,2,4]:
            K=int(W*FPS); sim=patchcorr(P[nm],e,K)
            sim[e-int(3*FPS):]=-1
            best=np.argmax(sim); rank=(sim>sim[g]).sum()
            out.append('%s%.2g:gt%.2f best%.2f@%.2f r%d'%(nm,W,sim[g],sim[best],best/FPS,rank))
    print(tid,s0); print('   '+'\n   '.join(out))
