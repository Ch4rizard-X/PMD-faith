import json,re
T=json.load(open('/tmp/claude-0/sprites_extra/gen/tracker.json'))
S=json.load(open('/tmp/claude-0/pmd1/game/data/sprites.json'))
dirs=set(l.strip() for l in open('/tmp/claude-0/-home-claude/b45f1f4c-6175-5669-9669-df3d43149e57/scratchpad/dirs.txt'))
SUF={'M':'Mega','MX':'Mega_X','MY':'Mega_Y','p':'Purple'}
out={}; miss=[]
for k in S:
    m=re.fullmatch(r'(\d{4})(\w*)',k); n,suf=m.groups()
    if not suf: d=f'sprite/{n}'
    else:
        want=SUF[suf]; d=None
        for sid,c in T.get(n,{}).get('subgroups',{}).items():
            if c.get('name')==want: d=f'sprite/{n}/{sid}'
    if d and d in dirs: out[k]=d
    else: miss.append((k,d))
json.dump(out,open('/tmp/claude-0/sprites_extra/gen/keymap.json','w'),indent=0)
print(len(out),'mapped; missing:',miss)
print({k:v for k,v in out.items() if not k.isdigit()})
