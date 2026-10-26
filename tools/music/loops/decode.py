import subprocess, numpy as np, csv, os, sys
from concurrent.futures import ThreadPoolExecutor
SR=22050
rows=[r for r in csv.DictReader(open('/tmp/claude-0/up/eos/eos_audio/music_list.csv')) if r['kind']=='music']
os.makedirs('pcm',exist_ok=True)
def dec(r):
    tid='%03d'%int(r['id']); out='pcm/%s.npy'%tid
    if os.path.exists(out): return
    p=subprocess.run(['ffmpeg','-v','error','-i','/tmp/claude-0/up/eos/eos_audio/'+r['file'],'-ac','1','-ar',str(SR),'-f','f32le','-'],capture_output=True)
    np.save(out,np.frombuffer(p.stdout,dtype=np.float32))
with ThreadPoolExecutor(4) as ex: list(ex.map(dec,rows))
