import numpy as np, scipy.signal as ss, sys, json, csv
from score import *
COMBO=['M0.5','M1','M2','C0.5','C1','C2']
def end_candidates(x,P,e0):
    r=P['rms']; db=20*np.log10(r+1e-9)
    sm=np.convolve(db,np.ones(4)/4,'same')
    cands=[(0,e0)]
    lo=int(e0-3.5*FPS)
    for i in range(max(lo,int(4*FPS)),e0-int(0.1*FPS)):
        before=np.median(sm[i-int(1.0*FPS):i]); after=sm[i+int(0.25*FPS)]
        drop=before-after
        # local: steepest point
        if drop>12 and sm[i]-sm[i+4]>3: cands.append((drop,i))
    # keep distinct, top 5
    cands.sort(key=lambda c:-c[0]); out=[e0]
    for d,i in cands[1:]:
        if all(abs(i-j)>0.2*FPS for j in out): out.append(i)
        if len(out)>=6: break
    return out
def analyse(x,combo=COMBO,verbose=False):
    P=prep(x); dur=len(x)/SR; e0=int(round((dur-2.0)*FPS))
    best=None
    for e in end_candidates(x,P,e0):
        tot=np.mean([patchcorr(P[k[0]],e,int(float(k[1:])*FPS)) for k in combo],0)
        lim=min(int(0.6*e),e-int(8*FPS))
        if lim<int(0.3*FPS): continue
        c=tot[:lim].copy(); c[:int(0.2*FPS)]=-1
        pk,_=ss.find_peaks(c,distance=int(0.1*FPS))
        if len(pk)==0: continue
        o=pk[np.argsort(-c[pk])]; b=o[0]
        far=[p for p in o if abs(p-b)>0.5*FPS]; sec=c[far[0]] if far else -1
        pen=0 if e==e0 else 0.03+0.01*(e0-e)/FPS
        sc=c[b]-pen
        # parabolic refine
        if 0<b<len(c)-1:
            a,m,z=c[b-1],c[b],c[b+1]; den=a-2*m+z; off=0.5*(a-z)/den if den<0 else 0
        else: off=0
        if verbose: print('   e=%.3f s=%.3f sc=%.3f raw=%.3f 2nd=%.3f'%(e/FPS,(b+off)/FPS,sc,c[b],sec))
        if best is None or sc>best['sc']:
            best=dict(s=(b+off)/FPS,e=e/FPS,sc=sc,raw=c[b],sec=sec,e0=e0/FPS)
    return best
if __name__=='__main__':
    GT={'011':(4.0,30.0),'015':(0,45.283),'017':(0.057,100.057),'018':(3.582,118.433),'016':(32.821,133.378),'134':(0.476,48.730),'123':(15.0,77.0)}
    for t,(s0,e0) in GT.items():
        print(t,s0,e0); b=analyse(np.load('pcm/%s.npy'%t),verbose=True); print('  ->',b)
