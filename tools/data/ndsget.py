import struct,sys
def read_file(rom, path):
    d=open(rom,'rb').read()
    fnt_off,fnt_len,fat_off,fat_len=struct.unpack_from('<IIII',d,0x40)
    parts=path.strip('/').split('/')
    def dir_entries(did):
        off=struct.unpack_from('<I',d,fnt_off+8*(did&0xFFF))[0]
        first=struct.unpack_from('<H',d,fnt_off+8*(did&0xFFF)+4)[0]
        p=fnt_off+off; fid=first
        while True:
            t=d[p]; p+=1
            if t==0: break
            ln=t&0x7F; name=d[p:p+ln].decode('latin-1'); p+=ln
            if t&0x80:
                sub=struct.unpack_from('<H',d,p)[0]; p+=2
                yield name,True,sub
            else:
                yield name,False,fid; fid+=1
    did=0xF000
    for i,part in enumerate(parts):
        for name,isdir,v in dir_entries(did):
            if name==part:
                if isdir: did=v
                else:
                    a,b=struct.unpack_from('<II',d,fat_off+8*v); return d[a:b]
                break
        else: raise KeyError(path)
sys.stdout.buffer.write(read_file(sys.argv[1],sys.argv[2]))
