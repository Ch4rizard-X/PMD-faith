import numpy as np, csv, json
from score import *
rows=[r for r in csv.DictReader(open('/tmp/claude-0/up/eos/eos_audio/music_list.csv')) if r['kind']=='music' and r['loops_in_game']=='True']
res={}
for r in rows:
    tid='%03d'%int(r['id']); x=np.load('pcm/%s.npy'%tid); P=prep(x)
    e=int(round((len(x)/SR-2.0)*FPS))
    if e<6*FPS: print(tid,'short',e/FPS); continue
    tot=np.zeros(e+1); parts={}
    for nm in 'MCX':
        for W in [0.5,1,2]:
            K=int(W*FPS); s=patchcorr(P[nm],e,K); parts[nm+str(W)]=s; tot+=s
    tot/=9; tot[e-int(4*FPS):]=-1
    b=int(np.argmax(tot))
    # second best peak away from b by >0.3s
    t2=tot.copy(); t2[max(0,b-int(.3*FPS)):b+int(.3*FPS)]=-1; b2=int(np.argmax(t2))
    res[tid]=(r['name'],b/FPS,tot[b],b2/FPS,tot[b2],e/FPS)
    print(tid,'%-40s best %.3f@%.3f  2nd %.3f@%.3f  e=%.3f'%(r['name'][:40],tot[b],b/FPS,tot[b2],b2/FPS,e/FPS),flush=True)
json.dump(res,open('survey.json','w'))
