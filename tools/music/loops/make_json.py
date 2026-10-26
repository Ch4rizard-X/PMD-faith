import json, numpy as np
R=json.load(open('raw.json')); out={}
for tid,v in sorted(R.items()):
    b=v['raw']; name=v['name']
    if b is None:
        x=np.load('pcm/%s.npy'%tid); h=1102
        env=np.array([np.sqrt(np.mean(x[i:i+h]**2)) for i in range(0,len(x),h)])
        db=20*np.log10(env+1e-9); last=np.nonzero(db>db.max()-30)[0][-1]
        end=min(len(x)/22050,(last+1)*h/22050)
        out[tid]=dict(start=0.0,end=round(end,3),conf=0.1,name=name,seq_end=round(len(x)/22050,3),method='short-ambient: whole sounding part',flag=True)
        continue
    S=b['S']; s,e=b['s'],b['e']
    if abs(b['rs']-s)<1.5 and b['sb']==b['sb'] and b['sb']>=0.4: s,e=b['rs'],b['re']
    rec=dict(name=name,seq_end=round(b['e0'],3),score=round(S,3),cand_start=round(s,3),cand_end=round(e,3))
    if S>=0.8:
        rec.update(start=round(s,3),end=round(e,3),conf=round(0.8+0.2*min(1,(S-0.8)/0.15),2),method='seam-match',flag=False)
    elif S>=0.65:
        rec.update(start=round(s,3),end=round(e,3),conf=round(0.5+0.25*(S-0.65)/0.15,2),method='seam-match (medium)',flag=False)
    else:
        rec.update(start=0.0,end=round(b['e0'],3),conf=round(min(0.3,0.1+0.2*max(S,0)),2),method='fallback: loop whole sequence',flag=True)
    if rec['end']<b['e0']-0.3: rec['method']+='; early musical end (render continues with leftover voices)'
    out[tid]=rec
json.dump(out,open('loops.json','w'),indent=1)
GT={'011':(4.0,30.0),'015':(0,45.283),'017':(0.057,100.057),'018':(3.582,118.433),'016':(32.821,133.378),'134':(0.476,48.730),'123':(15.0,77.0)}
for t,(s0,e0) in GT.items():
    r=out[t]; print(t,r['name'],'got %.3f/%.3f conf %.2f  gt %.3f/%.3f  err %+.3f/%+.3f'%(r['start'],r['end'],r['conf'],s0,e0,r['start']-s0,r['end']-e0))
hi=[t for t,r in out.items() if r['conf']>=0.8]; med=[t for t,r in out.items() if 0.5<=r['conf']<0.8]; lo=[t for t,r in out.items() if r['conf']<0.5]
print('high',len(hi),'medium',len(med),'low',len(lo),'total',len(out))
print('MED:',', '.join('%s %s (%.2f-%.2f)'%(t,out[t]['name'],out[t]['start'],out[t]['end']) for t in med))
print('LOW:',', '.join('%s %s'%(t,out[t]['name']) for t in lo))
print('HIGH:',', '.join('%s %s (%.2f-%.2f)'%(t,out[t]['name'],out[t]['start'],out[t]['end']) for t in hi))
