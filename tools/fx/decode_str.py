import json,struct,sys
def decode(path):
    d=open(path,'rb').read()
    n=struct.unpack_from('<I',d,0)[0]//4
    offs=list(struct.unpack_from('<%dI'%n,d,0))
    out=[]
    for o in offs:
        e=d.find(b"\0",o)
        if e<0: e=len(d)
        out.append(d[o:e].decode('cp1252',errors='replace'))
    return out
if __name__=='__main__':
    s=decode(sys.argv[1]); json.dump(s,open(sys.argv[2],'w'),ensure_ascii=False)
